import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ScheduleStore")
@MainActor
struct ScheduleStoreTests {
    private func schedule(_ name: String) -> AgentSchedule {
        AgentSchedule(
            id: UUID(), name: name,
            trigger: .time(cron: CronExpression(minutes: [0], hours: [9], daysOfWeek: nil)),
            prompt: "summarize inbox", agentID: nil, enabled: true,
            posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: "workspace-write"))
    }

    @Test func upsertPersists() {
        let p = InMemoryPersistenceStore()
        let store = ScheduleStore(persistence: p)
        let s = schedule("morning")
        store.upsert(s)
        #expect(ScheduleStore(persistence: p).schedules.contains { $0.id == s.id })
    }

    @Test func setEnabledToggles() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let s = schedule("x")
        store.upsert(s)
        store.setEnabled(s.id, false)
        #expect(store.schedules.first { $0.id == s.id }?.enabled == false)
    }

    @Test func recordFiredStampsLastRun() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let s = schedule("x")
        store.upsert(s)
        let runID = UUID()
        let when = Date(timeIntervalSince1970: 42)
        store.recordFired(s.id, runID: runID, date: when)
        #expect(store.schedules.first { $0.id == s.id }?.lastRunID == runID)
        #expect(store.schedules.first { $0.id == s.id }?.lastFired == when)
    }

    @Test func codableTriggerRoundTrips() throws {
        let t = ScheduleTrigger.fileChange(path: "/tmp/x", glob: "*.swift")
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(ScheduleTrigger.self, from: data) == t)
    }

    /// M7 Wave B (B2) — an unrecognized trigger kind (a future case this build
    /// doesn't know yet) decodes to `.unknown` rather than throwing and losing
    /// the whole `AgentSchedule`/`SchedulesDocument`.
    @Test func unrecognizedTriggerKindDecodesToUnknown() throws {
        let payload = #"{"futureKind":{"someField":"x"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScheduleTrigger.self, from: payload)
        #expect(decoded == .unknown)
    }

    /// M7 Wave B (B3) — `.webhook` no longer carries an independent id; a
    /// stale pre-fix payload shaped like the old `.webhook(id:)` case still
    /// decodes (id ignored, never a divergence source) rather than throwing.
    @Test func webhookTriggerRoundTripsWithoutAnID() throws {
        let data = try JSONEncoder().encode(ScheduleTrigger.webhook)
        #expect(try JSONDecoder().decode(ScheduleTrigger.self, from: data) == .webhook)

        let stalePayload = #"{"webhook":{"id":"some-random-id"}}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(ScheduleTrigger.self, from: stalePayload) == .webhook)
    }

    /// M7 Wave B (B3) — the fix's core invariant: nothing in `ScheduleTrigger`
    /// can carry an id that diverges from the owning `AgentSchedule.id` (the
    /// real webhook path — `WebhookServer`/`TriggerDispatcher` — has always
    /// keyed off `schedule.id`, never the trigger's own payload).
    @Test func webhookScheduleUsesOwningScheduleIDEverywhere() {
        let s = AgentSchedule(
            name: "hook", trigger: .webhook, prompt: "x",
            posture: SavedExecutionPosture(permissionMode: "ask"))
        // There is no id on `.webhook` to inspect/diverge — `schedule.id` is
        // the only identity a webhook trigger has, by construction.
        #expect(s.trigger == .webhook)
    }
}
