import AinkradHostRuntime
import Foundation

/// Provisions the single `.webhook` schedule that backs the remote channel.
/// The endpoint is `/hook/<schedule.id>`; the POST body becomes the run prompt
/// (`TriggerDispatcher` appends `event.payload` to `channelPrompt`). Reuses the
/// existing autonomy pipeline verbatim — no new dispatch code.
@MainActor
enum RemoteChannelProvisioner {
    /// A neutral preamble; the remote message is appended as `[trigger payload]`
    /// by `TriggerDispatcher.fire`, so it drives the turn.
    static let channelPrompt = "You are being driven over the remote channel. Respond to the following request."

    @discardableResult
    static func ensureChannelSchedule(in store: ScheduleStore, existing: UUID?) -> AgentSchedule {
        if let existing, let found = store.schedules.first(where: { $0.id == existing }) {
            return found
        }
        let schedule = AgentSchedule(
            name: "Remote channel",
            trigger: .webhook,
            prompt: channelPrompt,
            enabled: true,
            posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: nil))
        store.upsert(schedule)
        return schedule
    }
}
