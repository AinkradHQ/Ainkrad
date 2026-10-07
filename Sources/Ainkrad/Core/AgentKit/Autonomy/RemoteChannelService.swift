import AinkradHostRuntime
import Foundation
import Observation

enum RemoteChannelStatus: Equatable { case off, needsToken, listening, stopped }

/// Owns the `WebhookServer` lifecycle for the remote channel. Starts the server
/// ONLY when the channel is enabled AND a token exists in `SecretStore`. Reuses
/// the existing `TriggerDispatcher` (schedule-webhook path) verbatim.
@MainActor
@Observable
final class RemoteChannelService {
    private(set) var isRunning = false
    private let settingsStore: RemoteChannelSettingsStore
    private let scheduleStore: ScheduleStore
    private let dispatcher: TriggerDispatcher
    private let runs: RunManager
    private var server: WebhookServer?

    init(
        settingsStore: RemoteChannelSettingsStore, scheduleStore: ScheduleStore,
        dispatcher: TriggerDispatcher, runs: RunManager
    ) {
        self.settingsStore = settingsStore
        self.scheduleStore = scheduleStore
        self.dispatcher = dispatcher
        self.runs = runs
    }

    static func status(enabled: Bool, hasToken: Bool, running: Bool) -> RemoteChannelStatus {
        guard enabled else { return .off }
        guard hasToken else { return .needsToken }
        return running ? .listening : .stopped
    }

    var status: RemoteChannelStatus {
        Self.status(
            enabled: settingsStore.settings.enabled,
            hasToken: settingsStore.token != nil, running: isRunning)
    }

    /// Idempotent: called on launch and whenever settings change.
    func applyEnabledState() {
        let s = settingsStore.settings
        guard s.enabled, let token = settingsStore.token, !token.isEmpty else {
            stop()
            return
        }

        let schedule = RemoteChannelProvisioner.ensureChannelSchedule(
            in: scheduleStore, existing: s.channelScheduleID)
        if s.channelScheduleID != schedule.id { settingsStore.setChannelSchedule(schedule.id) }

        stop()
        let channelID = schedule.id.uuidString
        let server = WebhookServer(
            port: s.port, token: token, dispatcher: dispatcher,
            schedulesProviding: { [channelID] },
            resultProviding: { [weak self] id in
                guard let self else { return "{\"status\":\"unknown\"}" }
                return RemoteReplyResolver.body(forRunID: id, in: self.runs)
            })
        do {
            try server.start()
            self.server = server
            isRunning = true
        } catch {
            Log.persistence.error("Remote channel failed to start on port \(s.port, privacy: .public)")
            isRunning = false
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }
}
