import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("RunTerminalTool streaming", .timeLimit(.minutes(1)))
@MainActor
struct RunTerminalStreamTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }

    @Test func publishesLiveOutputForTheActiveCall() async throws {
        let stream = ToolStreamStore()
        stream.begin("call-1")  // the session normally does this at the pre-tool point
        let hub = AgentActionRegistryHub()
        let router = hostRouter()
        var tool = RunTerminalTool(actionHub: hub, router: router)
        tool.toolStream = stream
        let result = try await tool.execute(.object(["command": .string("echo streaming-works")]))
        #expect(result.content.contains("streaming-works"))
        // The live buffer received the output (the tool appended to the active call).
        #expect(stream.liveOutput(for: "call-1")?.contains("streaming-works") == true)
    }
}
