import AinkradHostRuntime
// Tests/AinkradTests/AgentSessionModelResolutionTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession model resolution")
@MainActor
struct AgentSessionModelResolutionTests {
    @Test func pinnedModelOverridesRouter() async {
        // Build a session with a router that would pick local, a runtime pin to opus,
        // and candidates covering both. resolveTurnForTesting exposes the resolved model.
        let resolved = await TestSessionFactory.resolveWithPin("claude-opus-4-8")
        #expect(resolved.model == "claude-opus-4-8")
    }

    @Test func routerPicksWhenNoPin() async {
        let resolved = await TestSessionFactory.resolveTrivialNoPin()
        #expect(resolved.tier == .local)  // free-first
    }

    /// Regression: a user pin to a LIVE-DISCOVERED model (e.g. an OpenRouter model
    /// id) that is absent from the preset-derived candidate list must still be
    /// honored on the ACTIVE connection — the router must NOT silently free-first
    /// route to some other connection's free model (the `llama3.2`-on-Ollama bug).
    @Test("a pin absent from the candidate list is honored on the active connection, not free-first routed")
    func pinAbsentFromCandidatesHonoredOnActiveConnection() async {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        // Active connection: OpenRouter, pinned to a discovered model NOT in any preset.
        let openRouter = connections.addConnection(
            preset: ProviderPreset.preset(id: "openrouter"),
            displayName: "OpenRouter", baseURL: ProviderPreset.preset(id: "openrouter").defaultBaseURL, token: "k")
        // A separate LOCAL connection whose free llama3.2 the buggy router would grab.
        let ollama = connections.addConnection(
            preset: ProviderPreset.preset(id: "ollama"),
            displayName: "Ollama", baseURL: ProviderPreset.preset(id: "ollama").defaultBaseURL, token: "")

        let config = AgentConfigStore(persistence: persistence)
        config.setActiveConnectionID(openRouter.id)
        config.setModel("nvidia/nemotron-nano-9b-v2:free")
        let runtime = RuntimeOptionsStore(persistence: persistence)
        runtime.pinModel("nvidia/nemotron-nano-9b-v2:free")
        let router = ModelRouter(catalog: ModelCatalog(), outcomes: RouterOutcomeStore(persistence: persistence))
        // Candidates DELIBERATELY exclude the pinned model and offer only the free
        // local one on the OTHER connection.
        let candidates: [RouterCandidate] = [
            RouterCandidate(
                connectionID: ollama.id, model: "llama3.2",
                descriptor: ModelDescriptor(
                    id: "llama3.2", tier: .local, contextWindow: 128_000, capabilities: [.toolUse]))
        ]
        let session = AgentSession(
            providerFor: { _ in RecordingProvider(script: []) },
            connections: connections, config: config,
            context: AgentContextService(
                hub: AgentContextRegistryHub(), settings: AgentContextSettingsStore(persistence: persistence)),
            registry: AgentToolRegistry(tools: []),
            permissions: AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() }),
            router: router, runtime: runtime, candidatesProvider: { candidates })

        let resolved = await session.resolveTurnForTesting()
        #expect(resolved.model == "nvidia/nemotron-nano-9b-v2:free")  // pin honored, not llama3.2
        #expect(resolved.connection?.id == openRouter.id)  // on the active connection, not Ollama
    }

    // MARK: - Invariant 1: router is opt-in / overridable

    @Test("a disabled Agent router honors the first candidate, NOT the router's free-first auto-pick")
    func disabledRouterUsesDefaultNotAutoPick() async {
        let persistence = InMemoryPersistenceStore()
        let agentStore = AgentStore(persistence: persistence)
        let disabledRouting = AgentRouting(routerEnabled: false)
        let profile = agentStore.add(
            AgentProfile(
                name: "NoRouter", instructions: "", toolPolicy: .all,
                defaultModel: "claude-opus-4-8", routing: disabledRouting))
        agentStore.setActive(profile.id)

        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let connection = connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let router = ModelRouter(catalog: ModelCatalog(), outcomes: RouterOutcomeStore(persistence: persistence))
        // Deliberately list the PREMIUM candidate first — if the router auto-picked
        // (free-first), it would reorder to the local one regardless of list order.
        let candidates: [RouterCandidate] = [
            RouterCandidate(
                connectionID: connection.id, model: "claude-opus-4-8",
                descriptor: ModelDescriptor(
                    id: "claude-opus-4-8", tier: .premium, contextWindow: 200_000,
                    capabilities: [.vision, .toolUse, .reasoningEffort])),
            RouterCandidate(
                connectionID: connection.id, model: "qwen2.5-coder",
                descriptor: ModelDescriptor(
                    id: "qwen2.5-coder", tier: .local, contextWindow: 32_000,
                    capabilities: [.toolUse])),
        ]
        let session = TestSessionFactory.make(
            agents: agentStore, connections: connections, persistence: persistence,
            router: router, candidatesProvider: { candidates })
        let resolved = await session.resolveTurnForTesting()
        #expect(resolved.model == "claude-opus-4-8")
        #expect(resolved.decision?.reason.contains("disabled") == true)
    }

    // MARK: - Invariant 5: everything degrades safely

    @Test("no router / no candidatesProvider: resolves to the standing config model, exactly like pre-Task-16")
    func noRouterNoCandidatesFallsBackToConfigCurrent() async {
        let session = TestSessionFactory.make(configModel: "claude-sonnet-4-8")
        let resolved = await session.resolveTurnForTesting()
        #expect(resolved.model == "claude-sonnet-4-8")
        #expect(resolved.decision == nil)
    }

    @Test("no candidatesProvider even WITH a router injected: still degrades to pin/default/config, never crashes")
    func routerPresentButNoCandidatesDegradesCleanly() async {
        let persistence = InMemoryPersistenceStore()
        let router = ModelRouter(catalog: ModelCatalog(), outcomes: RouterOutcomeStore(persistence: persistence))
        let session = TestSessionFactory.make(
            configModel: "gpt-5", persistence: persistence, router: router, candidatesProvider: nil)
        let resolved = await session.resolveTurnForTesting()
        #expect(resolved.model == "gpt-5")
    }

    // MARK: - Invariant 3: failover is bounded + classifies correctly

    @Test("FailoverController.classify: retryable provider errors are classified, content/user errors are not")
    func classifyRetryableVsContentErrors() {
        #expect(FailoverController.classify("HTTP 429: rate limit exceeded") == .rateLimit)
        #expect(FailoverController.classify("insufficient_quota: billing required") == .quota)
        #expect(FailoverController.classify("401 unauthorized: invalid api key") == .auth)
        #expect(FailoverController.classify("529 overloaded_error, please retry") == .providerError)
        #expect(FailoverController.classify("503 service unavailable") == .providerError)
        // Genuine content/user errors — must NEVER be retried.
        #expect(FailoverController.classify("400 bad request: invalid_request_error") == nil)
        #expect(FailoverController.classify("404 not found") == nil)
        #expect(FailoverController.classify("completely unrecognized error shape") == nil)
    }

    /// A scripted provider that fails for one model (with a retryable message) and
    /// succeeds for another, so the session-level failover walk can be exercised
    /// end-to-end (not just `FailoverController`'s pure step function in isolation).
    private final class TwoModelFailoverProvider: LLMProvider {
        private(set) var calledModels: [String] = []
        func send(
            messages: [AgentMessage], system: String, tools: [AgentToolSchema],
            model: AgentModelConfig, credential: ProviderCredential
        ) -> AsyncThrowingStream<AgentEvent, Error> {
            calledModels.append(model.model)
            let events: [AgentEvent] =
                model.model == "model-a"
                ? [.failed("529 overloaded_error")]
                : [.textDelta("ok"), .done(stopReason: "end_turn")]
            return AsyncThrowingStream { continuation in
                for e in events { continuation.yield(e) }
                continuation.finish()
            }
        }
    }

    @Test(
        "a retryable failure on the primary model fails over to the next candidate on the SAME connection and succeeds")
    func failoverAdvancesToNextModelOnRetryableError() async {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let connection = connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let candidates: [RouterCandidate] = [
            RouterCandidate(
                connectionID: connection.id, model: "model-a",
                descriptor: ModelDescriptor(
                    id: "model-a", tier: .premium, contextWindow: 200_000, capabilities: [.toolUse])),
            RouterCandidate(
                connectionID: connection.id, model: "model-b",
                descriptor: ModelDescriptor(
                    id: "model-b", tier: .premium, contextWindow: 200_000, capabilities: [.toolUse])),
        ]
        let usage = UsageTracker(persistence: persistence, prices: ModelPriceTable())
        let provider = TwoModelFailoverProvider()
        let config = AgentConfigStore(persistence: persistence)
        config.setModel("model-a")  // the degraded-path (no router) resolution: fallback == config.current.model
        let session = AgentSession(
            providerFor: { _ in provider },
            connections: connections, config: config,
            context: AgentContextService(
                hub: AgentContextRegistryHub(), settings: AgentContextSettingsStore(persistence: persistence)),
            registry: AgentToolRegistry(tools: []),
            permissions: AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() }),
            usage: usage, candidatesProvider: { candidates })
        session.send("hi")
        await session.currentTask?.value

        #expect(provider.calledModels == ["model-a", "model-b"])  // bounded: exactly one retry
        #expect(session.state == .idle)
        #expect(session.messages.last == AgentMessage(role: .assistant, text: "ok"))

        // Invariant 4: usage is attributed to the model ACTUALLY used (model-b), not
        // the originally-resolved model-a.
        #expect(session.lastUsageAttributedModel == "model-b")
    }

    @Test("a non-retryable content error does NOT loop through other candidates")
    func nonRetryableContentErrorDoesNotFailover() async {
        final class BadRequestProvider: LLMProvider {
            private(set) var callCount = 0
            func send(
                messages: [AgentMessage], system: String, tools: [AgentToolSchema],
                model: AgentModelConfig, credential: ProviderCredential
            ) -> AsyncThrowingStream<AgentEvent, Error> {
                callCount += 1
                return AsyncThrowingStream { continuation in
                    continuation.yield(.failed("400 bad request: invalid_request_error"))
                    continuation.finish()
                }
            }
        }
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let connection = connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "k")
        let candidates: [RouterCandidate] = [
            RouterCandidate(
                connectionID: connection.id, model: "model-a",
                descriptor: ModelDescriptor(
                    id: "model-a", tier: .premium, contextWindow: 200_000, capabilities: [.toolUse])),
            RouterCandidate(
                connectionID: connection.id, model: "model-b",
                descriptor: ModelDescriptor(
                    id: "model-b", tier: .premium, contextWindow: 200_000, capabilities: [.toolUse])),
        ]
        let provider = BadRequestProvider()
        let session = AgentSession(
            providerFor: { _ in provider },
            connections: connections, config: AgentConfigStore(persistence: persistence),
            context: AgentContextService(
                hub: AgentContextRegistryHub(), settings: AgentContextSettingsStore(persistence: persistence)),
            registry: AgentToolRegistry(tools: []),
            permissions: AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() }),
            candidatesProvider: { candidates })
        session.send("hi")
        await session.currentTask?.value

        #expect(session.state == .failed("400 bad request: invalid_request_error"))
        #expect(provider.callCount == 1)  // no retry across model-a/model-b for a content error
    }
}
