import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MenuBar wiring")
@MainActor
struct MenuBarWiringTests {
    /// Sleeps far longer than any of these tests run, so an enqueued run stays
    /// `.running` long enough to observe through the adapter. Unlike a bare
    /// `withCheckedContinuation`, `Task.sleep` responds to cancellation
    /// cleanly (no leaked-continuation misuse warning) once `RunManager.stop`
    /// or process teardown cancels the in-flight task.
    final class HangingRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        {
            try? await Task.sleep(for: .seconds(300))
            return .failure("did not complete in test")
        }
    }

    @Test func adapterMapsActiveRunsToItems() async {
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: HangingRunner())
        let run = mgr.enqueue(prompt: "build feature")
        // Let the enqueue → pump → start sequence settle onto `.running`.
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let adapter = RunManagerMenuBarAdapter(manager: mgr)
        let items = adapter.activeRunItems
        #expect(items.contains { $0.id == run.id && $0.title == "build feature" && $0.isActive })
    }

    @Test func adapterStopRunForwardsToManager() async {
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: HangingRunner())
        let run = mgr.enqueue(prompt: "long task")
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let adapter = RunManagerMenuBarAdapter(manager: mgr)
        adapter.stopRun(run.id)
        #expect(mgr.runs.first { $0.id == run.id }?.status == .interrupted)
    }

    @Test func emptySourceReportsNoRuns() {
        // Slice-3-independent guard: the empty adapter reports nothing.
        let empty = EmptyMenuBarRunSource()
        #expect(empty.activeRunItems.isEmpty)
    }
}
