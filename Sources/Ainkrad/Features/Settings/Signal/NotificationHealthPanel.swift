import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Whether notifications are working: how many arrived, how many were read,
/// how fast.
///
/// The "Loudest" list used to live here, with a Quiet button on each row, so
/// that the diagnosis and the remedy were one click. That rule still holds —
/// the remedy simply moved somewhere better. The loudest kind is now named on
/// its own source's row in the Sources list, where the control that silences
/// it already is, so this readout no longer needs a second copy of a source
/// list or a second way to change a setting.
///
/// Plain content, not an `AinkradSettingsPanel`: it is rendered inside one.
struct NotificationHealthPanel: View {
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

    @Binding var window: Window
    let health: SignalHealth

    @Environment(\.ainkradTheme) private var theme

    /// Under this, the numbers describe noise rather than behaviour. Saying so
    /// beats rendering "0% read" at someone who has had three notifications.
    private static let minimumSample = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AinkradCaption("Delivery stats, measured from your own feed and kept on "
                           + "this machine.")
            if health.total < Self.minimumSample {
                AinkradCaption("Not enough history yet.")
            } else {
                AinkradCaptionedRow("Window") {
                    AinkradSegmentedPicker(items: Window.allCases,
                                           selection: $window,
                                           label: \.label)
                }
                figures
            }
        }
    }

    private var figures: some View {
        HStack(spacing: AinkradSpacing.lg) {
            figure("Arrived", "\(health.total)")
            figure("Read", Self.percent(health.readRate))
            figure("Median reply", Self.duration(health.medianAcknowledgeSeconds))
        }
    }

    private func figure(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(AinkradFont.mono(15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.foreground)
            Text(caption)
                .font(AinkradFont.display(9.5))
                .foregroundStyle(theme.foreground.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    /// Whole percents. A read rate quoted to a decimal place claims a
    /// precision a few dozen events cannot support.
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
