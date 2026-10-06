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
/// `.transition`; the busy/installing state crossfades the primary button
/// with an `AinkradSpinner` in place (both views stay mounted; only opacity
/// changes — no structural swap) rather than showing a detached
/// `ProgressView`. All motion is skipped when `ainkradReduceMotion` is set —
/// state still updates, just without animation.
struct AppStoreActionControls: View {
    enum Style: Equatable {
        case card
        case detail

        var fontSize: CGFloat { self == .detail ? 12 : 11 }
        var spinnerSize: CGFloat { self == .detail ? 18 : 14 }
        var spacing: CGFloat { self == .detail ? 10 : 8 }
        var showsUninstall: Bool { self == .detail }
        /// Enable/disable + Uninstall live on the detail page only; grid cards
        /// carry just the install/update action (or the Installed label).
        var showsEnableToggle: Bool { self == .detail }
    }

    let row: AppStoreRow
    let tokens: DesignTokens
    let isBusy: Bool
    var style: Style = .card
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void

    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: style.spacing) {
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
            case .installed:
                installedLabel
                    .transition(rowTransition)
                manageControls
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: row.status)
    }

    /// The detail page's enable toggle (or the MCP-manager hint) and
    /// Uninstall, shown beside an installed app's primary control. Empty on
    /// grid cards.
    @ViewBuilder private var manageControls: some View {
        if style.showsEnableToggle && row.kind != .mcpServer {
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

    private var installedLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: style.fontSize - 1))
            Text("Installed").font(.system(size: style.fontSize, weight: .medium))
        }
        .foregroundStyle(tokens.accentTertiary)
    }

    /// A labeled `AinkradToggle` — the kit's chamfered switch, plus the
    /// Enabled/Disabled caption the bespoke pill used to carry.
    private var enableToggle: some View {
        HStack(spacing: 6) {
            AinkradToggle(isOn: Binding(get: { row.isEnabled }, set: onToggleEnabled))
            Text(row.isEnabled ? "Enabled" : "Disabled")
                .font(.system(size: style.fontSize, weight: .medium))
                .foregroundStyle(row.isEnabled ? tokens.accentTertiary : tokens.foreground.opacity(0.55))
        }
        .help(row.isEnabled ? "Disable" : "Enable")
    }

    /// MCP-server rows delegate enable/trust to the MCP manager (Task 11) —
    /// this hint replaces the enable toggle so a re-install (which resets
    /// enabled/trusted to false, per `MCPServerInstaller`) reads as "go
    /// re-trust this in the MCP manager" rather than a broken toggle.
    private var mcpManagerHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: style.fontSize - 1))
            Text("Add secrets & enable in MCP Servers")
                .font(.system(size: style.fontSize - 1, weight: .medium))
        }
        .foregroundStyle(tokens.foreground.opacity(0.55))
        .help("Enable, trust, and configure secrets for this MCP server in Settings → MCP Servers")
    }

    /// An `AinkradButton` that, while `morphsBusy && isBusy`, crossfades to
    /// an `AinkradSpinner` in place. Both views are always mounted — only
    /// `.opacity` toggles — so this never swaps the button's identity.
    private func actionButton(
        _ title: String, style buttonStyle: AinkradButtonStyle, morphsBusy: Bool, action: @escaping () -> Void
    ) -> some View {
        let showsSpinner = morphsBusy && isBusy
        return ZStack {
            AinkradButton(title: title, style: buttonStyle, action: action)
                .opacity(showsSpinner ? 0 : 1)
            AinkradSpinner(size: style.spinnerSize)
                .opacity(showsSpinner ? 1 : 0)
        }
        .disabled(isBusy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsSpinner)
    }
}
