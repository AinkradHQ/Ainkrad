import AinkradHostRuntime
// Tests/AinkradTests/Autonomy3aWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("Autonomy 3a wiring")
@MainActor
struct Autonomy3aWiringTests {
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("ok") }
    }

    @Test func spawnSubagentToolConstructsInRegistry() {
        let coordinator = SubagentCoordinator(runner: SubagentCoordinatorTests_EchoRunner())
        let registry = AgentToolRegistry(tools: [
            ReadFileTool(),
            SpawnSubagentTool(
                coordinator: coordinator,
                agents: AgentStore(persistence: InMemoryPersistenceStore())),
        ])
        #expect(registry.tool(named: "spawn_subagent") != nil)
    }

    @Test func runManagerEnqueuesChatOriginRun() {
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: InstantRunner())
        let run = mgr.enqueue(prompt: "bg task", origin: .chat)
        #expect(mgr.runs.contains { $0.id == run.id })
    }

    /// Verifies the production `makeSession` seam (`AppEnvironment.makeSubagentSession`,
    /// wired into `AgentSessionSubagentRunner` in `AppEnvironment.bootstrap`) builds
    /// children `unattended: true` (Task 8's requireApproval-auto-denies gate — a
    /// background/subagent run must never wedge on a HUD nobody can answer) with the
    /// router-resolved model PINNED (via a scoped `RuntimeOptionsStore`, no router/
    /// candidatesProvider passed to the child) rather than re-routed per turn.
    @Test func productionMakeSessionSeamBuildsUnattendedPinnedChild() {
        let persistence = InMemoryPersistenceStore()
        let connections = ConnectionStore(persistence: persistence, secrets: InMemorySecretStore())
        let agentStore = AgentStore(persistence: persistence)
        let agentPermissionStore = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        let agentConfigStore = AgentConfigStore(persistence: persistence)
        let agentContextService = AgentContextService(
            hub: AgentContextRegistryHub(),
            settings: AgentContextSettingsStore(persistence: persistence))
        let registry = AgentToolRegistry(tools: [ReadFileTool()])
        let profile = agentStore.active

        let makeSession = AppEnvironment.makeSubagentSession(
            providerFor: { (_: Connection) -> LLMProvider in Autonomy3aWiringTests.StubProvider() },
            connections: connections, agentConfigStore: agentConfigStore,
            agentContextService: agentContextService, agentPermissionStore: agentPermissionStore,
            agentStore: agentStore, credentialResolver: { _ in [] })

        let child = makeSession(profile, registry, "claude-opus-4-8", [])
        #expect(child.unattendedForTesting == true)
        #expect(child.activeModelIDForCommands() == "claude-opus-4-8")
    }

    /// A no-op provider — this test never actually sends a turn, it only inspects
    /// how the child `AgentSession` was constructed.
    @MainActor
    final class StubProvider: LLMProvider {
        func send(
            messages: [AgentMessage], system: String, tools: [AgentToolSchema],
            model: AgentModelConfig, credential: ProviderCredential
        ) -> AsyncThrowingStream<AgentEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}

// A tiny shared echo runner for wiring tests.
final class SubagentCoordinatorTests_EchoRunner: SubagentRunner {
    func run(_ spec: SubagentSpec) async -> SubagentOutcome {
        SubagentOutcome(id: spec.id, status: .succeeded, resultText: "ok")
    }
}
