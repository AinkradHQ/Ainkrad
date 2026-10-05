import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("TriggerDispatcher")
@MainActor
struct TriggerDispatcherTests {
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("ok") }
    }
    private func make() -> (ScheduleStore, RunManager, TriggerDispatcher, AgentSchedule) {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: InstantRunner())
        let s = AgentSchedule(
            name: "on change",
            trigger: .fileChange(path: "/repo", glob: "*.swift"),
            prompt: "run tests", posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: nil))
        store.upsert(s)
        return (store, runs, TriggerDispatcher(store: store, runs: runs, minInterval: 5), s)
    }

    @Test func firingEnqueuesEventRunWithPayload() {
        let (_, runs, disp, s) = make()
        let id = disp.fire(TriggerEvent(scheduleID: s.id, payload: "Foo.swift"), now: Date(timeIntervalSince1970: 0))
        #expect(id != nil)
        let run = runs.runs.first { $0.id == id }
        #expect(run?.origin == .event)
        #expect(run?.prompt.contains("run tests") == true)
        #expect(run?.prompt.contains("Foo.swift") == true)
    }

    @Test func rateLimitSuppressesSecondEventInWindow() {
        let (_, _, disp, s) = make()
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(disp.fire(TriggerEvent(scheduleID: s.id, payload: "a"), now: t0) != nil)
        #expect(disp.fire(TriggerEvent(scheduleID: s.id, payload: "b"), now: t0.addingTimeInterval(1)) == nil)
        #expect(disp.fire(TriggerEvent(scheduleID: s.id, payload: "c"), now: t0.addingTimeInterval(6)) != nil)
    }

    @Test func disabledScheduleDoesNotFire() {
        let (store, _, disp, s) = make()
        store.setEnabled(s.id, false)
        #expect(disp.fire(TriggerEvent(scheduleID: s.id, payload: "x")) == nil)
    }

    /// A burst of schedule() calls coalesces into a single trailing invocation.
    @Test func debouncerCoalescesBurst() async {
        let debouncer = Debouncer(interval: 0.05)
        final class Counter { var n = 0 }
        let counter = Counter()
        for _ in 0..<5 { debouncer.schedule { counter.n += 1 } }
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(counter.n == 1)
    }
}
