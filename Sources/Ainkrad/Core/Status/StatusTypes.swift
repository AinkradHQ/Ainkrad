import Foundation

/// The machine's current network reachability, shown as an item in the
/// full-screen status bar (AIN-109). `SystemStatusMonitor` derives this from
/// `NWPathMonitor`; kept as a plain enum here so the label/symbol mapping is
/// unit-testable without any system provider.
enum NetworkStatus: Equatable {
    case wifi
    case ethernet
    case offline
    case other

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .offline: return "Offline"
        case .other: return "Connected"
        }
    }

    var symbolName: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .offline: return "wifi.slash"
        case .other: return "network"
        }
    }
}

/// A snapshot of the machine's battery, shown as an item in the full-screen
/// status bar. `SystemStatusMonitor.battery` is `nil` when the machine has no
/// battery (e.g. a desktop Mac) — the item is hidden entirely in that case,
/// never shown with a placeholder value.
struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool

    var displayText: String { "\(percent)%" }

    /// A pure mapping from percent + charging state to the closest
    /// `battery.*` SF Symbol. While charging, always the bolt glyph
    /// (`battery.100.bolt` is the only bolt variant SF Symbols ships).
    var symbolName: String {
        guard !isCharging else { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Pure clock formatting for the full-screen status bar's time & date item —
/// deliberately takes `Date` as a parameter (never reads `Date()` itself) so
/// it is unit-testable with a fixed instant.
enum StatusClock {
    /// Formats `date` into a short time string ("10:13 PM") and a short
    /// date string ("Tue, Nov 14"), both localized to `calendar`/`locale`.
    static func string(from date: Date, calendar: Calendar = .current, locale: Locale = .current) -> (
        time: String, date: String
    ) {
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = locale
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("j:mm")

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = locale
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("EEE MMM d")

        return (timeFormatter.string(from: date), dateFormatter.string(from: date))
    }
}
