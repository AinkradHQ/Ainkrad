import AinkradHostRuntime
import Foundation

extension AgentSession {
    /// Thrown when `runConversation` needs a subscription credential but no
    /// `credentialResolver` was injected — every construction site outside
    /// `bootstrapAgentSessionAndRuns`'s main session (subagent/background
    /// sessions) doesn't wire subscription OAuth yet. Caught immediately and
    /// turned into the same re-auth `.failed` message as a live store throw.
    private enum CredentialResolutionError: Error { case oauthResolverUnavailable }

    // MARK: - Loop

    func runConversation() async {
        var iterations = 0
        let resolved = await resolveTurn()
        guard let connection = resolved.connection else {
            state = .failed("No connection configured. Add one in Sage settings.")
            return
        }
        let allKeys = authProfiles?.keys(for: connection) ?? (connections.token(for: connection).map { [$0] } ?? [])
        if connection.authMode == .apiKey,
            ProviderPreset.preset(id: connection.presetID).requiresKey, allKeys.isEmpty
        {
            state = .failed("No API key configured for \(connection.displayName)")
            return
        }

        let credentials: [ProviderCredential]
        do {
            if let resolver = credentialResolver {
                credentials = try await resolver(connection)
            } else if connection.authMode == .subscription {
                throw CredentialResolutionError.oauthResolverUnavailable
            } else {
                credentials = (allKeys.isEmpty ? [""] : allKeys).map { .apiKey($0) }
            }
        } catch {
            state = .failed(
                "Your Claude subscription needs to be re-authorized. " + "Open Sage settings and sign in again.")
            return
        }
        // A resolver that yields no credentials would otherwise crash the subscript below.
        guard let firstCredential = credentials.first else {
            state = .failed("No credentials available for \(connection.displayName).")
            return
        }

        let contextBlock = context.assembleContext()
        let agentInstructions = agents?.active.instructions ?? ""
        let promptHead = agentInstructions.isEmpty ? basePrompt : basePrompt + "\n\n" + agentInstructions
        let system = contextBlock.isEmpty ? promptHead : promptHead + "\n\n" + contextBlock
        let provider = providerFor(connection)

        var currentModel = resolved.modelConfig
        var currentCredential = firstCredential
        var didOpeningFailover = false

        while true {
            // Cooperative cancellation: `reset()` cancels this task (and unwedges
            // any parked approval). Bail BEFORE re-sending so a reset never spawns
            // a zombie turn that resurrects the just-cleared transcript.
            if Task.isCancelled { return }

            let outcome: TurnOutcome
            if !didOpeningFailover {
                let models = failoverModels(primary: currentModel.model, connectionID: connection.id)
                let (result, usedModel, usedCredential) = await runOneTurnWithFailover(
                    provider: provider, system: system, model: currentModel, models: models, credentials: credentials)
                outcome = result
                currentModel = AgentModelConfig(model: usedModel, effort: currentModel.effort)
                currentCredential = usedCredential
                didOpeningFailover = true
            } else {
                outcome = await runOneTurn(
                    provider: provider, system: system, model: currentModel, credential: currentCredential)
            }

            switch outcome {
            case .failed(let message):
                streamingText = ""
                streamingThinking = ""
                streamingBlocks = []
                let isLocal = isLocalConnection?(connection) ?? false
                state = .failed(Self.actionableFailureMessage(message, connection: connection, isLocal: isLocal))
                recordSettlement(success: false, resolved: resolved, usedModel: currentModel.model)
                return
            case .completed:
                streamingText = ""
                streamingThinking = ""
                streamingBlocks = []
                state = .idle
                recordSettlement(success: true, resolved: resolved, usedModel: currentModel.model)
                settled()
                return
            case .toolCalls(let calls, let assistantText, let thinking):
                iterations += 1
                if iterations > maxToolIterations {
                    messages.append(
                        AgentMessage(
                            role: .assistant,
                            text: (assistantText.isEmpty ? "" : assistantText + "\n\n")
                                + "Stopped: reached the \(maxToolIterations)-step tool limit."))
                    state = .idle
                    settled()
                    return
                }
                // Commit the assistant turn (thinking + text + tool_use blocks).
                var assistantBlocks: [AgentContentBlock] = []
                if !thinking.isEmpty { assistantBlocks.append(.thinking(thinking)) }
                if !assistantText.isEmpty { assistantBlocks.append(.text(assistantText)) }
                assistantBlocks.append(contentsOf: calls.map { .toolUse(id: $0.id, name: $0.name, input: $0.input) })
                messages.append(AgentMessage(role: .assistant, content: assistantBlocks))

                // Execute each call behind the gate; gather results into one user turn.
                var resultBlocks: [AgentContentBlock] = []
                for call in calls {
                    let result = await execute(call)
                    // A reset during a parked approval cancels this task while
                    // suspended inside `execute`. Bail before recording the
                    // (denied) result so `messages` stays cleared and `.idle` holds.
                    if Task.isCancelled { return }
                    resultBlocks.append(
                        .toolResult(toolUseID: call.id, content: result.content, isError: result.isError))
                }
                messages.append(AgentMessage(role: .user, content: resultBlocks))
                streamingText = ""
                streamingThinking = ""
                streamingBlocks = []
            // loop: re-send with the appended results
            }
        }
    }

    /// Turns a generic connection-failure message into an actionable one when the
    /// failing connection is LOCAL (Ollama/LM Studio/other loopback) — the common
    /// case being the server just isn't running, which the generic provider message
    /// ("Streaming failed: Could not connect to the server.") gives the user no way
    /// to act on. Any other failure (remote provider, or a local-connection failure
    /// that isn't connectivity-shaped, e.g. an auth error) passes through unchanged.
    /// Pure/testable: no I/O, no actor isolation required.
    nonisolated static func actionableFailureMessage(_ message: String, connection: Connection, isLocal: Bool) -> String
    {
        guard isLocal, message.lowercased().contains("connect") else { return message }
        return "Can't reach the local model server at \(connection.baseURL). "
            + "Start Ollama/LM Studio, or switch models (pick a model in the picker or /model <id>)."
    }

    private enum TurnOutcome {
        case completed
        case failed(String)
        case toolCalls([ToolCall], assistantText: String, thinking: String)
    }

    private func runOneTurn(
        provider: LLMProvider, system: String,
        model: AgentModelConfig, credential: ProviderCredential
    ) async -> TurnOutcome {
        let signpost = AinkradSignposts.begin(AinkradSignposts.agent, "agent-turn")
        defer { AinkradSignposts.end(AinkradSignposts.agent, "agent-turn", signpost) }
        state = .thinking
        streamingText = ""
        streamingThinking = ""
        streamingBlocks = []
        var textParser = MarkdownStreamParser()
        var coalescer = StreamCoalescer()
        var pendingThinking = ""
        var pendingPublish = false
        var pendingCalls: [ToolCall] = []
        var failure: String?
        var sawDone = false
        var turnUsage = TokenUsage.zero

        let stream = provider.send(
            messages: messages, system: system,
            tools: allowedSchemas(), model: model, credential: credential)
        do {
            for try await event in stream {
                switch event {
                case .thinkingDelta(let d):
                    pendingThinking += d
                    pendingPublish = true
                    if state != .thinking { state = .thinking }
                    publishIfDue(&coalescer, &textParser, &pendingThinking, &pendingPublish)
                case .textDelta(let d):
                    // Cheap: appends to the parser's short pending tail. This is
                    // NOT the SwiftUI-invalidating step — `publishIfDue` is.
                    textParser.append(d)
                    pendingPublish = true
                    if state != .streaming { state = .streaming }
                    publishIfDue(&coalescer, &textParser, &pendingThinking, &pendingPublish)
                case .toolUseStart(_, let name): state = .callingTool(name)
                case .toolInputDelta: break
                case .toolUseComplete(let id, let name, let input):
                    pendingCalls.append(ToolCall(id: id, name: name, input: input))
                case .done: sawDone = true
                case .usage(let u): turnUsage = turnUsage + u
                case .failed(let m): failure = m
                }
            }
        } catch {
            flushStreaming(&textParser, &pendingThinking)
            return .failed(error.localizedDescription)
        }
        flushStreaming(&textParser, &pendingThinking)
        lastTurnUsage = turnUsage

        if let failure { return .failed(failure) }
        if !pendingCalls.isEmpty {
            return .toolCalls(pendingCalls, assistantText: streamingText, thinking: streamingThinking)
        }
        // No tool calls: commit any assistant text (with leading thinking), then settle.
        if !streamingText.isEmpty {
            var blocks: [AgentContentBlock] = []
            if !streamingThinking.isEmpty { blocks.append(.thinking(streamingThinking)) }
            blocks.append(.text(streamingText))
            messages.append(AgentMessage(role: .assistant, content: blocks))
            return .completed
        }
        // Empty text. A clean `.done` (tool-less/text-less end_turn) settles to
        // idle; a stream that ended WITHOUT `.done` is a wedge we finalize as a
        // failure so the re-entrancy guard never stays stuck.
        return sawDone ? .completed : .failed("The response ended unexpectedly.")
    }

    /// Publishes to the observable properties only when the coalescing window
    /// has elapsed. Everything between publishes is accumulated, not dropped.
    private func publishIfDue(
        _ coalescer: inout StreamCoalescer,
        _ parser: inout MarkdownStreamParser,
        _ thinking: inout String,
        _ pending: inout Bool
    ) {
        guard pending, coalescer.shouldPublish(at: ContinuousClock.now) else { return }
        streamingText = parser.text
        streamingBlocks = parser.blocks
        streamingThinking = thinking
        pending = false
    }

    /// Unconditional publish. Required at stream end (normal or error): the
    /// last window is almost never exactly full, and without this the final
    /// few tokens would never reach the view.
    private func flushStreaming(
        _ parser: inout MarkdownStreamParser,
        _ thinking: inout String
    ) {
        streamingText = parser.text
        streamingBlocks = parser.blocks
        streamingThinking = thinking
    }

    /// Wraps the FIRST HTTP call of a user turn in a bounded failover walk over
    /// `models × keys`, advancing via `FailoverController.nextAttempt` (the same pure
    /// step function `FailoverController.run` uses) on a retryable failure — see
    /// `FailoverController.classify`. A non-retryable content/user error returns
    /// immediately (no cycling through every candidate for an error that would fail
    /// identically against all of them). Driven manually here, rather than through
    /// `FailoverController.run`'s closure-based driver, because that generic static
    /// function isn't actor-isolated — handing it a `@MainActor`-capturing closure
    /// (this method needs `self.runOneTurn`) trips Swift 6's strict-concurrency
    /// sending check. The bound (`models.count * keys.count` attempts, mirroring
    /// `run`'s own bound) is enforced identically. Follow-up tool-loop iterations
    /// within the same turn do NOT re-run failover — they reuse whichever `(model,
    /// key)` this call settled on.
    private func runOneTurnWithFailover(
        provider: LLMProvider, system: String, model: AgentModelConfig,
        models: [String], credentials: [ProviderCredential]
    ) async -> (TurnOutcome, model: String, credential: ProviderCredential) {
        let keys = credentials.map { _ in "" }
        guard
            var current = FailoverController.nextAttempt(
                models: models, keys: keys, failedModel: nil, failedKeyIndex: nil, errorKind: .providerError
            )
        else {
            return (.failed("no candidates configured"), model.model, credentials.first ?? .apiKey(""))
        }

        let maxAttempts = max(models.count * credentials.count, 1)
        var lastOutcome: TurnOutcome = .failed("no candidates configured")
        for _ in 0..<maxAttempts {
            let attemptModel = AgentModelConfig(model: current.model, effort: model.effort)
            let outcome = await runOneTurn(
                provider: provider, system: system,
                model: attemptModel, credential: credentials[current.keyIndex])
            guard case .failed(let message) = outcome, let kind = FailoverController.classify(message) else {
                return (outcome, current.model, credentials[current.keyIndex])
            }
            lastOutcome = outcome
            guard
                let next = FailoverController.nextAttempt(
                    models: models, keys: keys,
                    failedModel: current.model, failedKeyIndex: current.keyIndex, errorKind: kind
                )
            else {
                return (outcome, current.model, credentials[current.keyIndex])
            }
            current = next
        }
        return (lastOutcome, current.model, credentials[current.keyIndex])
    }
}
