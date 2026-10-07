import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// A scripted `LLMProvider` double. `send` records whether it was invoked and
/// replays a fixed event script regardless of arguments.
@MainActor
final class FakeLLMProvider: LLMProvider {
    private(set) var wasCalled = false
    private(set) var lastSystem: String?
    private(set) var lastApiKey: String?
    private let script: [AgentEvent]

    init(script: [AgentEvent]) {
        self.script = script
    }

    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema], model: AgentModelConfig,
        credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        wasCalled = true
        lastSystem = system
        if case .apiKey(let k) = credential { lastApiKey = k }
        let events = script
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

@MainActor
private func makeSession(
    fake: FakeLLMProvider,
    connections: ConnectionStore,
    config: AgentConfigStore? = nil,
    context: AgentContextService? = nil,
    basePrompt: String = AgentSession.defaultPrompt,
    persistence: PersistenceStore = InMemoryPersistenceStore()
) -> AgentSession {
    let resolvedContext: AgentContextService
    if let context {
        resolvedContext = context
    } else {
        let hub = AgentContextRegistryHub()
        let contextSettings = AgentContextSettingsStore(persistence: persistence)
        resolvedContext = AgentContextService(hub: hub, settings: contextSettings)
    }
    let resolvedConfig = config ?? AgentConfigStore(persistence: persistence)
    let permissions = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
    return AgentSession(
        providerFor: { _ in fake },
        connections: connections,
        config: resolvedConfig,
        context: resolvedContext,
        registry: AgentToolRegistry(tools: []),
        permissions: permissions,
        basePrompt: basePrompt
    )
}

@MainActor
@Suite("AgentSession")
struct AgentSessionTests {
    @Test("successful stream: transcript + state settle to idle with full assistant text")
    func successfulStream() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        let fake = FakeLLMProvider(script: [
            .thinkingDelta("pondering "),
            .thinkingDelta("further"),
            .textDelta("Hello "),
            .textDelta("world"),
            .done(stopReason: "end_turn"),
        ])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")

        // User message appended synchronously, before the stream runs.
        #expect(session.messages.first == AgentMessage(role: .user, text: "hi"))

        await session.currentTask?.value

        #expect(session.state == .idle)
        #expect(session.streamingText == "")
        #expect(session.streamingThinking == "")
        // Thinking is now persisted as a leading `.thinking` block on the
        // committed assistant turn, so assert on the text/thinking projections
        // rather than full-message equality (which is order-sensitive).
        #expect(session.messages.last?.text == "Hello world")
        #expect(session.messages.last?.thinkingText == "pondering further")
        #expect(fake.wasCalled)
        #expect(fake.lastApiKey == "sk-test-123")
    }

    @Test("provider failure: state becomes .failed and no assistant message is appended")
    func providerFailure() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        let fake = FakeLLMProvider(script: [
            .textDelta("partial"),
            .failed("boom"),
        ])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")
        await session.currentTask?.value

        #expect(session.state == .failed("boom"))
        #expect(session.messages.last == AgentMessage(role: .user, text: "hi"))
        #expect(!session.messages.contains { $0.role == .assistant })
    }

    @Test("no connection for active provider: fails without calling the provider")
    func noConnectionConfigured() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        // No connections added.

        let fake = FakeLLMProvider(script: [.done(stopReason: "end_turn")])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")
        await session.currentTask?.value

        if case .failed = session.state {
            // expected
        } else {
            Issue.record("expected .failed state, got \(session.state)")
        }
        #expect(!fake.wasCalled)
        #expect(!session.messages.contains { $0.role == .assistant })
    }

    @Test("system prompt carries base prompt + workspace context when context is non-empty")
    func systemPromptWithContext() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        let hub = AgentContextRegistryHub()
        let registry = HostContextRegistry(appID: "terminal", hub: hub)
        _ = registry.register { AgentContextSnapshot(kind: "terminal", title: "Terminal — ~/proj", text: "buf") }
        let context = AgentContextService(hub: hub, settings: AgentContextSettingsStore(persistence: persistence))

        let fake = FakeLLMProvider(script: [.done(stopReason: "end_turn")])
        let session = makeSession(fake: fake, connections: connections, context: context, basePrompt: "BASE PROMPT")

        session.send("hi")
        await session.currentTask?.value

        let system = fake.lastSystem
        #expect(system?.contains("BASE PROMPT") == true)
        #expect(system?.contains("<workspace_context>") == true)
        #expect(system?.contains("Terminal — ~/proj") == true)
    }

    @Test("system prompt equals base prompt exactly when context is empty")
    func systemPromptWithoutContext() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        // Empty hub → assembleContext() returns "".
        let hub = AgentContextRegistryHub()
        let context = AgentContextService(hub: hub, settings: AgentContextSettingsStore(persistence: persistence))

        let fake = FakeLLMProvider(script: [.done(stopReason: "end_turn")])
        let session = makeSession(fake: fake, connections: connections, context: context, basePrompt: "BASE PROMPT")

        session.send("hi")
        await session.currentTask?.value

        #expect(fake.lastSystem == "BASE PROMPT")
    }

    @Test("re-entrant send while a turn is in flight is ignored")
    func reentrantSendIgnored() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        let fake = FakeLLMProvider(script: [.textDelta("reply"), .done(stopReason: "end_turn")])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("first")
        // The turn is now in flight (state == .thinking, its Task not yet run).
        #expect(session.state == .thinking)

        // Second call must be a full no-op: no user message added, state unchanged.
        session.send("second")
        #expect(session.state == .thinking)
        #expect(session.messages == [AgentMessage(role: .user, text: "first")])

        await session.currentTask?.value

        // First turn completes untouched; "second" never entered the transcript.
        #expect(session.state == .idle)
        #expect(
            session.messages == [
                AgentMessage(role: .user, text: "first"),
                AgentMessage(role: .assistant, text: "reply"),
            ])
    }

    @Test("stream finishes without .done but with partial text: commits assistant message and returns to idle")
    func streamEndsWithoutDoneCommitsPartialText() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        // No `.done` and no `.failed` — the stream just ends (dropped
        // connection / undecodable trailing events).
        let fake = FakeLLMProvider(script: [
            .textDelta("partial "),
            .textDelta("reply"),
        ])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")
        await session.currentTask?.value

        #expect(session.state == .idle)
        #expect(session.streamingText == "")
        #expect(session.streamingThinking == "")
        #expect(session.messages.last == AgentMessage(role: .assistant, text: "partial reply"))

        // The re-entrancy guard must not be wedged: a subsequent send works
        // (same fake replays the same script, but the point is it actually
        // runs rather than being silently ignored).
        session.send("again")
        #expect(session.state == .thinking)
        await session.currentTask?.value
        #expect(session.messages.contains(AgentMessage(role: .user, text: "again")))
    }

    @Test("stream finishes without .done and without any text: state becomes .failed")
    func streamEndsWithoutDoneAndNoTextFails() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        // Empty script: the stream finishes immediately with no events at all.
        let fake = FakeLLMProvider(script: [])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")
        await session.currentTask?.value

        #expect(session.state == .failed("The response ended unexpectedly."))
        #expect(session.streamingText == "")
        #expect(session.streamingThinking == "")
        #expect(!session.messages.contains { $0.role == .assistant })

        // Re-entrancy guard must not be wedged after a .failed finalization either.
        session.send("again")
        #expect(session.state == .thinking)
        await session.currentTask?.value
        #expect(session.messages.contains(AgentMessage(role: .user, text: "again")))
    }

    @Test(".done with empty streamingText appends no assistant bubble but still settles to idle")
    func doneWithEmptyTextAppendsNoBubble() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        // `.done` arrives without any preceding `.textDelta` — the model
        // produced no visible text this turn (e.g. tool-only turn, later
        // slice). No empty assistant bubble should be appended.
        let fake = FakeLLMProvider(script: [.done(stopReason: "end_turn")])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")
        await session.currentTask?.value

        #expect(session.state == .idle)
        #expect(session.messages == [AgentMessage(role: .user, text: "hi")])
        #expect(!session.messages.contains { $0.role == .assistant })
    }

    @Test("reset clears transcript and state")
    func resetClearsState() async {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let connections = ConnectionStore(persistence: persistence, secrets: secrets)
        connections.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-test-123")

        let fake = FakeLLMProvider(script: [.textDelta("hi"), .done(stopReason: "end_turn")])
        let session = makeSession(fake: fake, connections: connections, persistence: persistence)

        session.send("hi")
        await session.currentTask?.value
        #expect(!session.messages.isEmpty)

        session.reset()

        #expect(session.messages.isEmpty)
        #expect(session.state == .idle)
        #expect(session.streamingText == "")
        #expect(session.streamingThinking == "")
    }
}
