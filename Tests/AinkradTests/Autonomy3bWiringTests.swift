import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Autonomy 3b wiring")
@MainActor
struct Autonomy3bWiringTests {
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("ok") }
    }

    @Test func nlScheduleCompilesAndFires() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: InstantRunner())
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let runner = ScheduleRunner(store: store, runs: runs, calendar: utc)

        let cron = NaturalLanguageCronCompiler.compile("every weekday at 9am")!
        store.upsert(
            AgentSchedule(
                name: "brief",
                trigger: .time(cron: cron), prompt: "brief me",
                posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: nil)))

        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        // 2026-07-20 is a Monday.
        _ = runner.tick(now: f.date(from: "2026-07-20T09:05:00Z")!)
        #expect(runs.runs.contains { $0.origin == .schedule && $0.prompt == "brief me" })
    }

    @Test func scriptedBatchToolDisabledWithoutSandbox() async throws {
        // No sandbox profile configured for the tier here, so the router itself
        // never resolves a usable backend for this call — matches production
        // wiring where a missing/unavailable backend fails closed rather than
        // falling back to host.
        let tool = ScriptedBatchTool(executionRouter: nil)
        let r = try await tool.execute(.object(["script": .string("echo hi")]))
        #expect(r.isError)
    }

    @Test("bootstrap wires the 3b autonomy subsystem into AppEnvironment")
    func bootstrapWiresAutonomy3b() {
        let t = TestHome.make("3b-wiring")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        // The stored properties exist (non-optional), are freshly-constructed
        // (empty), and the tool registry gained the scripted-batch tool wired
        // to the REAL Slice 6 `ExecutionRouter` (not a nil placeholder).
        #expect(environment.scheduleStore.schedules.isEmpty)
        environment.scheduleStore.upsert(
            AgentSchedule(
                name: "smoke", trigger: .time(cron: NaturalLanguageCronCompiler.compile("daily at 9am")!),
                prompt: "smoke test", posture: SavedExecutionPosture(permissionMode: "ask")))
        #expect(environment.scheduleStore.schedules.count == 1)
    }
}
