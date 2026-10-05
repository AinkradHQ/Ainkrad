import Foundation
import Testing

@testable import Ainkrad

@Suite("TerminalProcessController", .timeLimit(.minutes(1)))
struct TerminalProcessControllerTests {
    @Test func killActiveTerminatesALongRunningChildEarly() async {
        let controller = TerminalProcessController()
        let runner = SandboxProcessRunner()
        let start = Date()
        async let running = runner.run(
            executable: "/bin/zsh", arguments: ["-lc", "sleep 30"],
            workingDir: NSHomeDirectory(), timeout: 60, controller: controller)
        // Give the child a moment to launch and register, then kill it.
        try? await Task.sleep(for: .milliseconds(300))
        controller.killActive()
        let result = await running
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 10, "expected killActive to end the 30s sleep early (elapsed \(elapsed)s)")
        _ = result  // exit status is irrelevant; the point is it returned promptly
    }

    @Test func killActiveWithNoProcessIsANoOp() {
        TerminalProcessController().killActive()  // must not crash
    }
}
