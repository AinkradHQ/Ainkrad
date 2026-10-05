import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("RemoteChannelProvisioner")
struct RemoteChannelProvisionerTests {
    @Test func provisionsWebhookScheduleOnce() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let first = RemoteChannelProvisioner.ensureChannelSchedule(in: store, existing: nil)
        if case .webhook = first.trigger {} else { Issue.record("expected .webhook trigger") }
        #expect(first.enabled)
        // idempotent when the same id is passed back
        let second = RemoteChannelProvisioner.ensureChannelSchedule(in: store, existing: first.id)
        #expect(second.id == first.id)
        #expect(
            store.schedules.filter { if case .webhook = $0.trigger { return true } else { return false } }.count == 1)
    }

    @Test func firingChannelScheduleEnqueuesRunWithPayloadPrompt() {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: NoopRunner())
        let schedule = RemoteChannelProvisioner.ensureChannelSchedule(in: store, existing: nil)
        let dispatcher = TriggerDispatcher(store: store, runs: runs, minInterval: 0)

        let runID = dispatcher.fire(TriggerEvent(scheduleID: schedule.id, payload: "summarize the repo"))
        #expect(runID != nil)
        let run = runs.runs.first { $0.id == runID }
        #expect(run?.origin == .event)
        #expect(run?.prompt.contains("summarize the repo") == true)
    }

    final class NoopRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("") }
    }
}
