import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Asks the user whether one app may read another's notifications.
///
/// This is the only consent prompt in the plugin contract, because generation
/// 10 added the first capability that lets one app see another's data. The
/// wording is therefore about what the app will be able to SEE, never about
/// what it declared: "Git Mage wants to read Raven's build notifications" is a
/// question; "gitmage declares app:raven/build.*" is configuration, and a
/// prompt that reads as configuration is one people click through.
///
/// **Deny does not block installation.** The app installs and simply observes
/// nothing — every other capability it has still works. Refusing one optional
/// permission must not cost the user the app, or the only safe answer becomes
/// the one that loses them something.
struct SubscriptionApprovalView: View {
    let appName: String
    let subscriptions: [SignalSubscription]
    /// Resolves an app id to its display name, from the host's registry.
    ///
    /// Injected rather than looked up here so the view stays renderable in a
    /// snapshot, and required because the SDK cannot know that "raven" is
    /// called "Raven" — the first cut showed the raw id beside "Sage" and
    /// "Ainkrad", which reads as a bug.
    var displayName: (String) -> String = { $0 }
    /// True when the app was already approved and has since widened its list —
    /// the user is being re-asked, and saying so is the difference between a
    /// prompt that looks like a bug and one that explains itself.
    var isReapproval: Bool = false
    var onAllow: () -> Void = {}
    var onDeny: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        AinkradPanel(showsBrackets: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                rows
                footer
            }
            .frame(width: 420)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AinkradSpacing.sm - 1) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accentSecondary)
                Text(isReapproval ? "Updated notification access" : "Notification access")
                    .font(AinkradFont.display(11.5, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                AinkradBadge(text: "\(subscriptions.count)", tint: theme.accentSecondary)
            }
            Text(isReapproval
                 ? "\(appName) has asked for more notification access than you approved before."
                 : "\(appName) wants to read notifications from other apps.")
                .font(AinkradFont.display(12))
                .foregroundStyle(theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// One row per subscription, in the app's own words via
    /// `approvalDescription`. Listed rather than summarised as a count: "3
    /// subscriptions" is not something anyone can consent to.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(subscriptions.enumerated()), id: \.offset) { _, subscription in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.accentPrimary.opacity(0.7))
                        .frame(width: 12)
                    Text(label(for: subscription))
                        // Mono, because it is a readout of a declared value
                        // rather than prose — the same rule the feed's
                        // timestamps and source labels follow.
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(theme.foreground.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                // A tint band per row, never a separator: the design language
                // forbids rules, and the rows still have to read as a list.
                .background(
                    ChamferShape(cut: AinkradRadius.sm)
                        .fill(theme.surfaceElevated.opacity(0.45)))
            }
        }
        .padding(.horizontal, 12)
    }

    /// "Raven: build.* notifications" — the source named as the user knows
    /// it, then the shape of what will be read.
    private func label(for subscription: SignalSubscription) -> String {
        let name: String
        if let builtIn = subscription.builtInSourceName {
            name = builtIn
        } else if case .app(let appID) = subscription.source {
            name = displayName(appID)
        } else {
            name = "Another app"
        }
        return "\(name): \(subscription.kindDescription)"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You can change this later in Settings › Notifications.")
                .font(AinkradFont.display(10.5))
                .foregroundStyle(theme.foreground.opacity(0.55))

            HStack(spacing: AinkradSpacing.sm) {
                Spacer()
                // Deny first in reading order and NOT styled as the primary
                // action: the safe answer must never be the one that takes
                // more effort to choose.
                Button(action: onDeny) {
                    Text("Don't allow")
                        .font(AinkradFont.display(11, weight: .medium))
                        .foregroundStyle(theme.foreground.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(ChamferShape(cut: AinkradRadius.sm)
                            .fill(theme.surfaceElevated.opacity(0.6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onAllow) {
                    Text("Allow")
                        .font(AinkradFont.display(11, weight: .semibold))
                        .foregroundStyle(theme.background)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(ChamferShape(cut: AinkradRadius.sm)
                            .fill(theme.accentPrimary))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }
}

/// The Settings section: every app that asked, what it may read, and a way to
/// take it back.
///
/// Shows DENIED apps too, not only approved ones. An app the user refused
/// months ago is exactly the thing they cannot otherwise discover — there is
/// no other surface where "Git Mage asked and I said no" is recoverable.
struct SubscriptionSettingsSection: View {
    struct Row: Identifiable {
        let id: String
        let appName: String
        let subscriptions: [SignalSubscription]
        let isApproved: Bool
    }

    let rows: [Row]
    var displayName: (String) -> String = { $0 }
    var onApprove: (String) -> Void = { _ in }
    var onRevoke: (String) -> Void = { _ in }

    @Environment(\.ainkradTheme) private var theme
    /// Revoke is a destructive control, so its colour comes from the shared
    /// `AinkradStatus` ramp rather than a literal red — the same source the
    /// feed's severities use, so a theme change moves both together.
    @Environment(\.ainkradStatusColors) private var statusColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cross-app notification access")
                .font(AinkradFont.display(11.5, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .textCase(.uppercase)
                .tracking(0.6)

            if rows.isEmpty {
                Text("No app has asked to read another app's notifications.")
                    .font(AinkradFont.display(11.5))
                    .foregroundStyle(theme.foreground.opacity(0.55))
                    .padding(.vertical, 10)
            } else {
                ForEach(rows) { row in
                    appRow(row)
                }
            }
        }
    }

    /// Neutral at rest, `danger` on hover.
    ///
    /// Full red at rest was tried and rejected on the rendered page: it was
    /// the loudest thing on an otherwise calm surface, and a control shouting
    /// before you have reached for it reads as a warning about the page rather
    /// than a description of the action. Hover is also what the design
    /// language asks for everywhere.
    private func revokeButton(_ row: Row) -> some View {
        RevokeButton(isApproved: row.isApproved,
                     danger: statusColors.danger,
                     accent: theme.accentPrimary,
                     resting: theme.foreground.opacity(0.7)) {
            row.isApproved ? onRevoke(row.id) : onApprove(row.id)
        }
    }

    private func settingsLabel(for subscription: SignalSubscription) -> String {
        let name: String
        if let builtIn = subscription.builtInSourceName {
            name = builtIn
        } else if case .app(let appID) = subscription.source {
            name = displayName(appID)
        } else {
            name = "Another app"
        }
        return "\(name): \(subscription.kindDescription)"
    }

    private func appRow(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AinkradSpacing.sm - 2) {
                Text(row.appName)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(theme.foreground)
                AinkradBadge(text: row.isApproved ? "Allowed" : "Not allowed",
                             tint: row.isApproved ? theme.accentSecondary
                                                  : theme.foreground.opacity(0.35))
                Spacer()
                revokeButton(row)
            }
            ForEach(Array(row.subscriptions.enumerated()), id: \.offset) { _, subscription in
                Text(settingsLabel(for: subscription))
                    .font(AinkradFont.mono(10.5))
                    .foregroundStyle(theme.foreground.opacity(row.isApproved ? 0.75 : 0.4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md)
            .fill(theme.surfaceElevated.opacity(0.4)))
    }
}

/// Split out so the hover state has somewhere to live.
private struct RevokeButton: View {
    let isApproved: Bool
    let danger: Color
    let accent: Color
    let resting: Color
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(isApproved ? "Revoke" : "Allow")
                .font(AinkradFont.display(10.5, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }

    private var tint: Color {
        guard isApproved else { return accent }
        return isHovering ? danger : resting
    }
}
