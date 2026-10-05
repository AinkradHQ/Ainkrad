import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession /remember")
@MainActor
struct AgentSessionMemoryHookTests {
    /// Never invoked: /remember is intercepted before any provider work starts.
    private struct UnusedProvider: LLMProvider {
        func send(
            messages: [AgentMessage], system: String, tools: [AgentToolSchema],
            model: AgentModelConfig, credential: ProviderCredential
        ) -> AsyncThrowingStream<AgentEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @Test func rememberInterceptsWithoutStartingATurn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rem-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        let persistence = InMemoryPersistenceStore()
        let session = AgentSession(
            providerFor: { _ in UnusedProvider() },
            connections: ConnectionStore(persistence: persistence, secrets: InMemorySecretStore()),
            config: AgentConfigStore(persistence: persistence),
            context: AgentContextService(
                hub: AgentContextRegistryHub(),
                settings: AgentContextSettingsStore(persistence: persistence)),
            registry: AgentToolRegistry(tools: []),
            permissions: AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() }),
            memory: svc,
            commands: CommandRegistry(
                builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil)))
        session.send("/remember call me Ahmed")
        #expect(session.messages.isEmpty)  // intercepted — no user turn appended
        #expect(session.state == .idle)  // no provider/connection path entered
        #expect(svc.store.read(.memory).contains("call me Ahmed"))
        #expect(svc.log.entries().first?.provenance == .remember)
    }
}
