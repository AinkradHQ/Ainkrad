import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
import SwiftUI

/// The notification bell in the app's own top bar, beside the workspace
/// diamonds.
///
/// It floats directly on the sky with no background tint and no separator,
/// matching `HUDBar`'s rule for that strip — the chamfered chip treatment
/// belongs to the readouts on the left (clock, network, battery), not here.
///
/// Living in-window rather than on `NSStatusBar` also means the first-run
/// setup gate covers it for free: the scrim is a full-screen surface inside
/// the window, so there is nothing here that can be reached around it.
struct SignalBellButton: View {
    let unread: Int
    /// Quiet hours or a snooze is in force. The bell says so, because silence
    /// the user cannot see is indistinguishable from breakage — and the support
    /// question it produces is "notifications stopped working".
    var isMuted: Bool = false
    /// Changes when something arrives. The bell reacts to the CHANGE, not the
    /// value, so any increment pulses once.
    var arrivalToken: Int = 0
    let tokens: DesignTokens
    let action: () -> Void

    @State private var isHovered = false
    @State private var pulse = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin

    /// Capped so a busy session cannot widen the bar and shove the workspace
    /// diamonds along.
    static func badgeText(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case ...99: return String(count)
        default: return "99+"
        }
    }

    /// Static and pure so the three-way choice is testable without rendering.
    static func glyphName(unread: Int, isMuted: Bool) -> String {
        if isMuted { return "bell.slash" }
        return unread > 0 ? "bell.fill" : "bell"
    }

    private var hasUnread: Bool { unread > 0 }

    /// Names the reason as well as the count. A muted bell with three unread is
    /// two facts, and the tooltip is the only place either is written down.
    private var helpText: String {
        let count =
            hasUnread
            ? "\(unread) unread notification\(unread == 1 ? "" : "s")"
            : "Notifications"
        return isMuted ? "\(count) — quiet hours are on" : count
    }

    var body: some View {
        // The label is the glyph, its count and the arrival pulse; no kit
        // button takes a custom label.
        Button(action: action) {  // design-lint: allow raw-control kit gap, content label
            HStack(spacing: skin.spacing.xs) {
                Image(systemName: Self.glyphName(unread: unread, isMuted: isMuted))
                    .font(skin.font(AinkradFontToken(sizeKey: "t10_5", weight: "medium", scaled: false)))
                    .foregroundStyle(
                        hasUnread
                            ? tokens.accentSecondary
                            : tokens.foreground.opacity(isHovered ? skin.opacity.o75 : skin.opacity.o40)
                    )
                    // The glyph is its own layer: it lifts on hover rather than
                    // the whole control moving.
                    // Hover and arrival multiply rather than fight: a pulse
                    // while hovered should still read as a pulse.
                    .scaleEffect((isHovered ? 1.14 : 1) * (pulse && !reduceMotion ? 1.18 : 1))
                    .opacity(pulse && reduceMotion ? skin.opacity.o55 : 1)
                    .shadow(
                        color: hasUnread || pulse
                            ? tokens.accentSecondary.opacity(pulse ? 1 : skin.opacity.o80) : .clear,
                        radius: pulse ? skin.size.s8 : skin.size.s4)

                if let badge = Self.badgeText(unread) {
                    Text(badge)
                        .font(AinkradFont.mono(9.5, weight: .semibold))
                        .foregroundStyle(tokens.accentSecondary)
                }
            }
            .frame(minWidth: skin.size.s14, minHeight: skin.size.s11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        // One element, one sentence — the same rule `SignalFeedRow` follows.
        // The glyph and the count are two separate views, so without this a
        // listener gets an unlabelled image and a bare number, and the muted
        // state — carried entirely by which glyph is drawn — is never spoken
        // at all. `helpText` already says both facts; it is reused rather than
        // written twice so the tooltip and the label cannot drift.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
        .accessibilityAddTraits(.isButton)
        .onChange(of: arrivalToken) { _, _ in
            guard arrivalToken > 0 else { return }
            // Out fast, back at the base duration — an arrival should catch
            // the eye and then stop asking for it.
            withAnimation(reduceMotion ? nil : .easeOut(duration: AinkradMotion.durationFast)) {
                pulse = true
            }
            Task {
                try? await Task.sleep(for: .seconds(AinkradMotion.durationFast))
                withAnimation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: AinkradMotion.durationBase)
                ) {
                    pulse = false
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: skin.motion.durations.d0_16)) { isHovered = hovering }
        }
    }
}
