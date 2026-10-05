import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Terminal streaming bootstrap wiring", .timeLimit(.minutes(1)))
@MainActor
struct TerminalStreamingBootstrapWiringTests {
    @Test func sameControllerInstanceKillsToolLaunchedChild() async throws {
        // Prove the wiring contract: one controller shared by the tool and the
        // caller of killActive kills the tool's child.
        let controller = TerminalProcessController()
        let stream = ToolStreamStore()
        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
        // Bound to a local (rather than passed as an inline temporary) so ARC
        // keeps it alive for the whole test — `RunTerminalTool.actionHub` is
        // `unowned`, and an un-named temporary can be deallocated as soon as
        // its last syntactic use passes, before `execute()` runs.
        let actionHub = AgentActionRegistryHub()
        var tool = RunTerminalTool(actionHub: actionHub, router: router)
        tool.toolStream = stream
        tool.processController = controller
        stream.begin("c1")
        async let running = tool.execute(.object(["command": .string("sleep 30")]))
        try? await Task.sleep(for: .milliseconds(400))
        let start = Date()
        controller.killActive()
        _ = try await running
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
