import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
import SwiftUI

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
    @Environment(\.ainkradSkin) private var skin

    /// The kit modal: it dims and blurs the window behind the prompt and pads
    /// the panel itself. Always presented while this view exists — the caller
    /// removes the view once the user answers — so the scrim and Esc, which
    /// try to dismiss, change nothing: only the two buttons answer.
    var body: some View {
        Color.clear
            .ainkradModal(
                isPresented: .constant(true), contentWidth: skin.size.s420 - 2 * skin.spacing.lg
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    rows
                    footer
                }
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            HStack(spacing: AinkradSpacing.sm - 1) {
                Image(systemName: "bell.badge")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "medium", scaled: false)))
                    .foregroundStyle(theme.accentSecondary)
                Text(isReapproval ? "Updated notification access" : "Notification access")
                    .font(AinkradFont.display(11.5, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                AinkradBadge(text: "\(subscriptions.count)", tint: theme.accentSecondary)
            }
            Text(
                isReapproval
                    ? "\(appName) has asked for more notification access than you approved before."
                    : "\(appName) wants to read notifications from other apps."
            )
            .font(AinkradFont.display(12))
            .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, skin.size.s10)
    }

    /// One row per subscription, in the app's own words via
    /// `approvalDescription`. Listed rather than summarised as a count: "3
    /// subscriptions" is not something anyone can consent to.
    private var rows: some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            ForEach(Array(subscriptions.enumerated()), id: \.offset) { _, subscription in
                HStack(alignment: .firstTextBaseline, spacing: skin.spacing.sm) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(skin.font(AinkradFontToken(sizeKey: "t9", weight: "semibold", scaled: false)))
                        .foregroundStyle(theme.accentPrimary.opacity(skin.opacity.o70))
                        .frame(width: skin.size.s12)
                    Text(label(for: subscription))
                        // Mono, because it is a readout of a declared value
                        // rather than prose — the same rule the feed's
                        // timestamps and source labels follow.
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, skin.spacing.md)
                .padding(.vertical, skin.size.s7)
                // A tint band per row, never a separator: the design language
                // forbids rules, and the rows still have to read as a list.
                .background(
                    skin.shape(cut: skin.radius.sm)
                        .fill(theme.surfaceElevated.opacity(skin.opacity.o45)))
            }
        }
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
        VStack(alignment: .leading, spacing: skin.size.s10) {
            Text("You can change this later in Settings › Notifications.")
                .font(AinkradFont.display(10.5))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o55))

            HStack(spacing: AinkradSpacing.sm) {
                Spacer()
                // Deny first in reading order and NOT styled as the primary
                // action: the safe answer must never be the one that takes
                // more effort to choose.
                AinkradButton(title: "Don't allow", style: .ghost, action: onDeny)
                AinkradButton(title: "Allow", style: .primary, action: onAllow)
            }
        }
        .padding(.top, skin.size.s14)
    }
}
