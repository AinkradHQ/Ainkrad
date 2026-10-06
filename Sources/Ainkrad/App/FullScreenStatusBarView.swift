import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The full-screen title strip's left-side status readouts (AIN-109) — the
/// region the system traffic lights vacate once the window goes full-screen.
/// Renders an ordered, extensible list of items (clock, network, battery —
/// skipped when there is none) in the HUD's mono/small-symbol language, so a
/// future item (e.g. CPU/memory) only needs a new `StatusBarItem` case and a
/// branch in `itemView`, not a one-off view.
///
/// Not `AinkradStatusBar`: the kit's status bar is a segmented gauge for one
/// value, with no clock, network or battery readout — a kit gap ("status
/// readout strip"). Local, on skin tokens.
struct FullScreenStatusBarView: View {
    let monitor: SystemStatusMonitor

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    /// Colours stay on `DesignTokens`, which carry the user's custom accent;
    /// every scalar comes from the skin.
    private var tokens: DesignTokens { environment.themeManager.tokens }

    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            ForEach(items) { item in
                itemView(item)
                    .padding(.horizontal, skin.spacing.sm)
                    .padding(.vertical, skin.spacing.xs)
                    .background(
                        ChamferShape(cut: skin.radius.sm).fill(tokens.surfaceElevated.opacity(skin.opacity.o32))
                    )
                    .overlay(
                        ChamferShape(cut: skin.radius.sm).strokeBorder(
                            tokens.surface.opacity(skin.opacity.o40), lineWidth: 1))
            }
        }
    }

    private var items: [StatusBarItem] {
        let clock = StatusClock.string(from: monitor.now)
        var result: [StatusBarItem] = [
            .clock(time: clock.time, date: clock.date),
            .network(monitor.network),
        ]
        if let battery = monitor.battery {
            result.append(.battery(battery))
        }
        return result
    }

    @ViewBuilder
    private func itemView(_ item: StatusBarItem) -> some View {
        switch item {
        case .clock(let time, let date):
            HStack(spacing: skin.size.s6) {
                Text(time)
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o85))
                Text(date)
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
            }
            .font(AinkradFont.mono(11, weight: .medium))
        case .network(let status):
            symbolReadout(status.symbolName, text: status.label)
        case .battery(let info):
            symbolReadout(info.symbolName, text: info.displayText)
        }
    }

    /// Network/battery readouts carry the theme's `accentSecondary` so the
    /// status bar reads as part of the current theme rather than flat neutral.
    /// The clock stays in `foreground` (see `itemView`) as the legible anchor.
    private func symbolReadout(_ symbolName: String, text: String) -> some View {
        HStack(spacing: skin.spacing.xs) {
            Image(systemName: symbolName)
                .font(skin.font(AinkradFontToken(sizeKey: "t10", scaled: false)))
                .foregroundStyle(tokens.accentSecondary.opacity(skin.opacity.o95))
            Text(text)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.accentSecondary.opacity(skin.opacity.o85))
        }
    }
}

/// One entry in the full-screen status bar's ordered item list.
private enum StatusBarItem: Identifiable {
    case clock(time: String, date: String)
    case network(NetworkStatus)
    case battery(BatteryInfo)

    var id: String {
        switch self {
        case .clock: return "clock"
        case .network: return "network"
        case .battery: return "battery"
        }
    }
}
