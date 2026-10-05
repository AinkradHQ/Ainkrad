import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Timeline live output")
@MainActor
struct TimelineLiveOutputTests {
    private func toolStep(id: String, status: StepStatus, resultText: String, isPending: Bool) -> TurnStep {
        TurnStep(
            id: id,
            kind: .tool(
                ToolStepPayload(
                    toolUseID: id, name: "run_terminal", input: .object([:]),
                    result: ToolResultSummary(text: resultText, isError: false, isPending: isPending))),
            status: status, duration: nil, tokens: nil)
    }

    @Test func runningStepPrefersLiveBuffer() {
        let store = ToolStreamStore()
        store.begin("t1")
        store.appendActive("$ echo hi\nhi\n")
        let step = toolStep(id: "t1", status: .running, resultText: "Running…", isPending: true)
        #expect(TimelineLiveOutput.summary(for: step, store: store).contains("hi"))
    }

    @Test func settledStepUsesCommittedResult() {
        let store = ToolStreamStore()
        let step = toolStep(id: "t1", status: .done, resultText: "$ echo hi\nhi\n[exit 0]", isPending: false)
        #expect(TimelineLiveOutput.summary(for: step, store: store) == "$ echo hi\nhi\n[exit 0]")
    }
}
