import Foundation

/// The stats window and number formatting the Notifications → Feed tab uses.
enum NotificationStats {
    enum Window: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day: return "24 hours"
            case .week: return "7 days"
            case .month: return "30 days"
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            }
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Coarse on purpose, for the same reason: the number is read as "about
    /// this long", and seconds of precision on a median of eleven samples is
    /// a decoration pretending to be data.
    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        switch seconds {
        case ..<60: return "\(Int(seconds.rounded()))s"
        case ..<3600: return "\(Int((seconds / 60).rounded()))m"
        case ..<86_400: return "\(Int((seconds / 3600).rounded()))h"
        default: return "\(Int((seconds / 86_400).rounded()))d"
        }
    }
}
