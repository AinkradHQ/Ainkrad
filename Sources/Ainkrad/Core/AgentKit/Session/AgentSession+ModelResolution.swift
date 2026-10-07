import Foundation

extension AgentSession {
    // MARK: - Model resolution (Task 16)

    /// One turn's resolved sending target: which connection/model to use, the
    /// `RouterDecision` that produced it (`nil` when the router path wasn't taken —
    /// no router injected, or no candidates available), and the premium baseline
    /// the router avoided (feeds `UsageTracker`'s savings math).
    struct ResolvedTurn: Sendable {
        let connection: Connection?
        let modelConfig: AgentModelConfig
        let tier: ModelTier
        let baselineModel: String?
        let decision: RouterDecision?
        var model: String { modelConfig.model }
    }

    /// Resolution order: session pin (`/model`) → router (bounded by the active
    /// Agent's routing envelope; a disabled router or an unmatched pin falls back to
    /// the first candidate) → Agent default model → the standing `AgentConfigStore`
    /// model. The router path is OPT-IN: it only runs when both a `router` is
    /// injected AND `candidatesProvider` yields at least one candidate — with either
    /// missing, resolution degrades to the pre-Task-16 pin/default/config chain.
    func resolveTurn() async -> ResolvedTurn {
        let pin = runtime?.options.pinnedModel
        var candidates = candidatesProvider?() ?? []

        // An explicit pin is an explicit override and MUST be honorable even when it
        // isn't in the preset-derived candidate list — e.g. a live-discovered model
        // id (an OpenRouter/Ollama model the user selected) that no `curatedModels`
        // enumerates. Without this, the router can't match the pin (it matches by
        // `candidate.model == pin`) and silently free-first routes to some OTHER
        // connection's free model. Synthesize a candidate for the pin on the ACTIVE
        // connection so the router's pin-match resolves it on the connection the user
        // actually chose. Uses the same conservative descriptor `candidatesProvider`
        // falls back to for a model the catalog doesn't recognize.
        if let pin, !candidates.contains(where: { $0.model == pin }), let active = activeConnection() {
            candidates.insert(
                RouterCandidate(
                    connectionID: active.id, model: pin,
                    descriptor: ModelDescriptor(
                        id: pin, tier: .cheapPaid, contextWindow: 128_000, capabilities: [.toolUse])),
                at: 0)
        }

        if let router, !candidates.isEmpty {
            let routing = agents?.active.routing ?? AgentRouting()
            let lastMessage = messages.last(where: { $0.role == .user })?.text ?? ""
            // `needsTools` signals that THIS turn requires tool-use capability, not
            // merely that the registry has tools available (nearly always true for an
            // agentic host) — without deeper message-intent analysis, the conservative
            // default is `false`, so a plain/trivial message can still free-first route
            // to a local model even though tools exist in the registry.
            let signal = TaskSignal(
                estimatedInputTokens: lastMessage.count / 4,
                needsVision: false, needsTools: false,
                reasoningHeavy: false)
            let request = RouterRequest(
                signal: signal, lastMessage: lastMessage, routing: routing,
                candidates: candidates, userPinnedModel: pin, attempt: 0)
            let decision = await router.route(request)
            let connection =
                connections.connections.first(where: { $0.id == decision.candidate.connectionID })
                ?? activeConnection()
            let effort = effortString(capabilities: decision.candidate.descriptor.capabilities)
            return ResolvedTurn(
                connection: connection,
                modelConfig: AgentModelConfig(model: decision.candidate.model, effort: effort),
                tier: decision.tier, baselineModel: decision.baselineModel, decision: decision)
        }

        // Degraded path (no router, or no candidates to route over): pin, else the
        // active Agent's default, else the standing config model — exactly the
        // pre-Task-16 behavior when `agents`/`runtime` are also both nil.
        let fallbackModel = pin ?? agents?.active.defaultModel ?? config.current.model
        let connection = activeConnection()
        return ResolvedTurn(
            connection: connection,
            modelConfig: AgentModelConfig(model: fallbackModel, effort: config.current.effort),
            tier: .premium, baselineModel: nil, decision: nil)
    }

    /// `/think`'s honest-scope check (and `resolveTurn`'s effort wiring) both need
    /// "does this model actually respect an effort dial" — only `ClaudeProvider` sends
    /// `output_config.effort`; other kinds ignore it. `capabilities: nil` (the degraded
    /// resolution path, where there is no descriptor) is treated as capable, matching
    /// pre-Task-16 behavior of always honoring `config.current.effort` unconditionally.
    private func effortString(capabilities: ModelCapability?) -> String {
        guard let capabilities, capabilities.contains(.reasoningEffort) else { return config.current.effort }
        switch runtime?.options.thinkLevel {
        case "low": return "low"
        case "medium": return "medium"
        case "high": return "high"
        case "max": return "xhigh"
        default: return config.current.effort
        }
    }

    /// Best-effort "what model is this session currently pointed at" for slash
    /// commands (`/think`'s capability notice) — NOT a substitute for `resolveTurn`,
    /// which also consults the router; this is synchronous and router-unaware.
    func activeModelIDForCommands() -> String {
        runtime?.options.pinnedModel ?? agents?.active.defaultModel ?? config.current.model
    }

    /// Models to walk on a retryable send failure: the resolved model first, then any
    /// other candidate on the SAME connection (failover swaps model/key, never
    /// connection — see `FailoverController`'s doc comment on the `(model, keyIndex)`
    /// ordering it assumes).
    func failoverModels(primary: String, connectionID: UUID) -> [String] {
        guard let candidatesProvider else { return [primary] }
        var ordered = [primary]
        for candidate in candidatesProvider() where candidate.connectionID == connectionID {
            if !ordered.contains(candidate.model) { ordered.append(candidate.model) }
        }
        return ordered
    }

    /// Records the turn's actual outcome — the model failover/escalation ACTUALLY
    /// used, not just the one `resolveTurn` originally picked — into the router's
    /// learning store and the usage ledger. Called once per settle (both the
    /// `.completed` and `.failed` exits of `runConversation`).
    func recordSettlement(success: Bool, resolved: ResolvedTurn, usedModel: String) {
        if let decision = resolved.decision {
            let effective =
                decision.candidate.model == usedModel
                ? decision
                : RouterDecision(
                    candidate: RouterCandidate(
                        connectionID: decision.candidate.connectionID,
                        model: usedModel, descriptor: decision.candidate.descriptor),
                    tier: decision.tier, reason: decision.reason,
                    escalated: decision.escalated, baselineModel: decision.baselineModel)
            router?.recordOutcome(effective, success: success)
        }
        usage?.record(model: usedModel, usage: lastTurnUsage, baselineModel: resolved.baselineModel)
        lastUsageAttributedModel = usedModel
    }
}
