import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("RemoteChannelService status")
struct RemoteChannelServiceTests {
    @Test func statusDerivation() {
        #expect(RemoteChannelService.status(enabled: false, hasToken: false, running: false) == .off)
        #expect(RemoteChannelService.status(enabled: true, hasToken: false, running: false) == .needsToken)
        #expect(RemoteChannelService.status(enabled: true, hasToken: true, running: true) == .listening)
        #expect(RemoteChannelService.status(enabled: true, hasToken: true, running: false) == .stopped)
    }

    @Test func disabledNeverStarts() {
        let secrets = InMemorySecretStore()
        let settings = RemoteChannelSettingsStore(persistence: InMemoryPersistenceStore(), secrets: secrets)
        _ = settings.rotateToken()  // token present…
        // …but enabled is false by default
        let scheduleStore = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: Noop())
        let dispatcher = TriggerDispatcher(store: scheduleStore, runs: runs, minInterval: 0)
        let service = RemoteChannelService(
            settingsStore: settings, scheduleStore: scheduleStore, dispatcher: dispatcher, runs: runs)
        service.applyEnabledState()
        #expect(service.isRunning == false)
    }

    @Test func enabledWithoutTokenNeverStarts() {
        let settings = RemoteChannelSettingsStore(
            persistence: InMemoryPersistenceStore(), secrets: InMemorySecretStore())
        settings.setEnabled(true)  // enabled but NO token
        let scheduleStore = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: Noop())
        let dispatcher = TriggerDispatcher(store: scheduleStore, runs: runs, minInterval: 0)
        let service = RemoteChannelService(
            settingsStore: settings, scheduleStore: scheduleStore, dispatcher: dispatcher, runs: runs)
        service.applyEnabledState()
        #expect(service.isRunning == false)
    }

    final class Noop: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("") }
    }
}
