import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ScheduleRunner")
@MainActor
struct ScheduleRunnerTests {
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("ok") }
    }
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: s)!
    }
    private func make() -> (ScheduleStore, RunManager, ScheduleRunner) {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: InstantRunner())
        return (store, runs, ScheduleRunner(store: store, runs: runs, calendar: utc))
    }
    private func daily9() -> AgentSchedule {
        AgentSchedule(
            name: "morning",
            trigger: .time(cron: CronExpression(minutes: [0], hours: [9], daysOfWeek: nil)),
            prompt: "brief me", posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: nil))
    }

    @Test func firesWhenDue() {
        let (store, runs, runner) = make()
        store.upsert(daily9())
        let fired = runner.tick(now: date("2026-07-18T09:00:30Z"))
        #expect(fired.count == 1)
        #expect(runs.runs.contains { $0.origin == .schedule && $0.prompt == "brief me" })
    }

    @Test func doesNotFireBeforeDue() {
        let (store, _, runner) = make()
        store.upsert(daily9())
        #expect(runner.tick(now: date("2026-07-18T08:59:00Z")).isEmpty)
    }

    @Test func coalescesMissedWindowIntoSingleRun() {
        let (store, runs, runner) = make()
        store.upsert(daily9())
        // App was asleep for two days; a single tick should fire ONCE, not twice.
        _ = runner.tick(now: date("2026-07-20T12:00:00Z"))
        #expect(runs.runs.filter { $0.origin == .schedule }.count == 1)
    }

    @Test func disabledDoesNotFire() {
        let (store, _, runner) = make()
        var s = daily9()
        s.enabled = false
        store.upsert(s)
        #expect(runner.tick(now: date("2026-07-18T09:30:00Z")).isEmpty)
    }
}
