import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The status-driven action controls — Install / Update / Enable / Disable /
/// Uninstall, plus the busy affordance — shared by `AppStoreCard` and
/// `AppStoreDetailView` (AIN-149) so the grid and the detail page never
/// diverge again. `style` scales type size/padding for the card's compact
/// row vs. the detail page's larger header; the callbacks, statuses, and
/// HUD styling are identical in both places.
///
/// Status transitions (available → installed, installed → updateAvailable,
/// …) animate via `.animation(value: row.status)` + per-child
/// `.transition`; the busy/installing state is the kit button's own loading
/// state, which crossfades its label to a spinner in place. All motion is
/// skipped when `ainkradReduceMotion` is set — state still updates, just
/// without animation.
struct AppStoreActionControls: View {
    enum Style: Equatable {
        case card
        case detail

        /// Type-size keys for the captions, and the gap between controls.
        var fontKey: String { self == .detail ? "t12" : "t11" }
        var smallFontKey: String { self == .detail ? "t11" : "t10" }
        func spacing(in skin: AinkradSkin) -> CGFloat { self == .detail ? skin.size.s10 : skin.spacing.sm }
        var showsUninstall: Bool { self == .detail }
        /// Enable/disable + Uninstall live on the detail page only; grid cards
        /// carry just the install/update action (or the Installed label).
        var showsEnableToggle: Bool { self == .detail }
    }

    let row: AppStoreRow
    let tokens: AinkradSkin
    let isBusy: Bool
    var style: Style = .card
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void
    /// Themes tab: make this installed theme or colour scheme the one in use.
    var onApply: () -> Void = {}

    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: style.spacing(in: skin)) {
            switch row.status {
            case .available:
                actionButton("Install", style: .primary, morphsBusy: true, action: onInstall)
                    .transition(rowTransition)
            case .updateAvailable:
                actionButton("Update", style: .primary, morphsBusy: true, action: onUpdate)
                    .transition(rowTransition)
                manageControls
            case .installed where row.needsRestart:
                actionButton(
                    "Restart to Apply", style: .primary, morphsBusy: false,
                    action: HostRelaunch.relaunch
                )
                .help("The update is installed. Ainkrad keeps running the old version until it restarts.")
                .transition(rowTransition)
            case .installed where row.kind.isTheme:
                applyControl
                manageControls
            case .installed:
                installedLabel
                    .transition(rowTransition)
                manageControls
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: skin.motion.durations.d0_32), value: row.status)
    }

    /// The detail page's enable toggle (or the MCP-manager hint) and
    /// Uninstall, shown beside an installed app's primary control. Empty on
    /// grid cards.
    @ViewBuilder private var manageControls: some View {
        if row.kind.isTheme {
            // A theme has no enable toggle; while an update waits it can still be applied.
            if style == .detail && row.status == .updateAvailable { applyControl }
        } else if style.showsEnableToggle && row.kind != .mcpServer {
            enableToggle
                .transition(rowTransition)
        } else if style.showsEnableToggle && row.kind == .mcpServer {
            mcpManagerHint
                .transition(rowTransition)
        }
        if style.showsUninstall && row.isManaged {
            actionButton("Uninstall", style: .danger, morphsBusy: false, action: onUninstall)
                .transition(rowTransition)
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .identity : .scale(scale: 0.9).combined(with: .opacity)
    }

    private var installedLabel: some View { statusLabel("Installed") }

    /// Apply, or "In Use" once this theme or scheme is the current one.
    @ViewBuilder private var applyControl: some View {
        if row.isApplied {
            statusLabel("In Use").transition(rowTransition)
        } else {
            actionButton("Apply", style: .secondary, morphsBusy: false, action: onApply)
                .help("Use this \(row.kind == .theme ? "theme" : "colour scheme") now")
                .transition(rowTransition)
        }
    }

    private func statusLabel(_ title: String) -> some View {
        HStack(spacing: skin.spacing.xs) {
            Image(systemName: "checkmark.circle.fill").font(font(style.smallFontKey))
            Text(title).font(font(style.fontKey, weight: "medium"))
        }
        .foregroundStyle(tokens.color(\.accentTertiary))
    }

    /// A labeled `AinkradToggle` — the kit's chamfered switch, plus the
    /// Enabled/Disabled caption the bespoke pill used to carry.
    private var enableToggle: some View {
        HStack(spacing: skin.size.s6) {
            AinkradToggle(isOn: Binding(get: { row.isEnabled }, set: onToggleEnabled))
            Text(row.isEnabled ? "Enabled" : "Disabled")
                .font(font(style.fontKey, weight: "medium"))
                .foregroundStyle(row.isEnabled ? tokens.color(\.accentTertiary) : tokens.color(\.foreground).opacity(skin.opacity.o55))
        }
        .help(row.isEnabled ? "Disable" : "Enable")
    }

    /// MCP-server rows delegate enable/trust to the MCP manager (Task 11) —
    /// this hint replaces the enable toggle so a re-install (which resets
    /// enabled/trusted to false, per `MCPServerInstaller`) reads as "go
    /// re-trust this in the MCP manager" rather than a broken toggle.
    private var mcpManagerHint: some View {
        HStack(spacing: skin.spacing.xs) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(font(style.smallFontKey))
            Text("Add secrets & enable in MCP Servers")
                .font(font(style.smallFontKey, weight: "medium"))
        }
        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o55))
        .help("Enable, trust, and configure secrets for this MCP server in Settings → MCP Servers")
    }

    /// An `AinkradButton` that shows its loading state while
    /// `morphsBusy && isBusy`. Every action is disabled while the app is busy.
    private func actionButton(
        _ title: String, style buttonStyle: AinkradButtonStyle, morphsBusy: Bool, action: @escaping () -> Void
    ) -> some View {
        AinkradButton(title: title, style: buttonStyle, isLoading: morphsBusy && isBusy, action: action)
            .disabled(isBusy)
    }

    /// A caption font from the skin's type-size ladder, unscaled like the
    /// fixed sizes it replaced.
    private func font(_ sizeKey: String, weight: String? = nil) -> Font {
        skin.font(AinkradFontToken(sizeKey: sizeKey, weight: weight, scaled: false))
    }
}
