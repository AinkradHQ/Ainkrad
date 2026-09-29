import Foundation
import AinkradSignal

/// An ad-hoc quiet spell, and the only place its durations are written down.
///
/// The dropdown used to offer one hour, Settings offered one hour or until
/// tomorrow, and the overlay offered nothing — the same action with three
/// different answers depending on where the user happened to be standing.
/// Every surface now renders THIS, in whatever chrome suits it.
enum SignalSnooze: String, CaseIterable, Identifiable {
    case hour
    case tomorrow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: return "Quiet for an hour"
        case .tomorrow: return "Quiet until tomorrow"
        }
    }

    /// When this snooze would end, starting now.
    ///
    /// `tomorrow` is 08:00 the next day — "until tomorrow" means until the
    /// working day, not until midnight, which would end it in the middle of
    /// the night.
    func until(after now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour:
            return now.addingTimeInterval(3600)
        case .tomorrow:
            let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: next) ?? next
        }
    }

    /// Writes into the SAME field quiet hours reads, so the two can never
    /// disagree about whether now is quiet.
    func apply(to suppression: inout SuppressionWindow,
               at now: Date, calendar: Calendar = .current) {
        suppression.snoozedUntil = until(after: now, calendar: calendar)
    }

    /// Ends the snooze and nothing else. A user ending an ad-hoc quiet spell
    /// has not asked to be woken at 3am, so the schedule survives.
    static func lift(_ suppression: inout SuppressionWindow) {
        suppression.snoozedUntil = nil
    }
}
