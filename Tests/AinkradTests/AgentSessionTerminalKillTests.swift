import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession terminal kill + stream", .timeLimit(.minutes(1)))
@MainActor
struct AgentSessionTerminalKillTests {
    @Test func interruptForceKillsARunningChild() async {
        let controller = TerminalProcessController()
        let stream = ToolStreamStore()
        // A provider that emits a single long-running run_terminal call.
        let session = TestSessionFactory.makeStreamingTerminal(
            controller: controller, toolStream: stream, command: "sleep 30")
        session.send("run it")
        // Let the child launch and register, then interrupt.
        try? await Task.sleep(for: .milliseconds(500))
        let start = Date()
        session.interrupt()
        await session.currentTask?.value
        #expect(Date().timeIntervalSince(start) < 10)  // the child was killed, not left for 30s
        #expect(session.state == .idle)
    }
}
