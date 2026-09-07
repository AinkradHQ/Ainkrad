import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The bell's dropdown: a compact glance at what just happened, wearing the
/// shared HUD panel finish (`AinkradPanel` — blur, chamfered clip, luminous
/// accent stroke, corner brackets) rather than a hand-rolled rectangle.
///
/// It shows only the most recent few events. "View all notifications" hands
/// off to the full feed overlay, which is where search, filters and history
/// live — a dropdown that tried to carry those would be the overlay, just
/// smaller and worse.
struct SignalBellDropdown: View {
    let events: [SignalEvent]
    let unread: Int
    var repeatCounts: [UUID: Int] = [:]
    var readIDs: Set<UUID> = []
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }
    var onMarkAllRead: () -> Void = {}
    var onViewAll: () -> Void = {}
    /// Quiet hours or a snooze is in force.
    var isMuted: Bool = false
    /// Go quiet, or come back. Offered HERE because this is where the user is
    /// when they notice the noise — sending them to Settings to stop it is
    /// asking them to go somewhere else to solve the problem in front of them.
    ///
    /// Both durations, not just the hour this surface used to hardcode: the
    /// same action offering different choices depending on where you invoked
    /// it is a worse fault than offering it in only one place.
    var onSnooze: (SignalSnooze) -> Void = { _ in }
    var onResume: () -> Void = {}

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    /// Tracked separately per control: one shared flag would light both the
    /// footer and "Mark all read" whenever the pointer touched either.
    @State private var hoveringFooter = false
    @State private var hoveringMarkAll = false

    /// Five is the most that fits without the dropdown becoming a scroll view,
    /// which is the point at which it should have been the overlay instead.
    private static let maxRows = 5

    private var shown: [SignalEvent] { Array(events.prefix(Self.maxRows)) }

    var body: some View {
        AinkradPanel(showsBrackets: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if shown.isEmpty {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { event in
                            SignalFeedRow(event: event,
                                          repeatCount: repeatCounts[event.id] ?? 1,
                                          isUnread: !readIDs.contains(event.id),
                                          now: now,
                                          onActivate: onActivate,
                                          onAction: onAction)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
                footer
            }
            .frame(width: 372)
        }
    }

    private var header: some View {
        HStack(spacing: AinkradSpacing.sm - 1) {
            Text("Notifications")
                .font(AinkradFont.display(11.5, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .textCase(.uppercase)
                .tracking(0.6)
            if unread > 0 {
                AinkradBadge(text: "\(unread)", tint: theme.accentSecondary)
            }
            Spacer()
            if isMuted {
                Button(action: onResume) { quietGlyph }
                    .buttonStyle(.plain)
                    .help("Resume now")
                    // Icon-only, so `help` is not enough: a tooltip is a
                    // pointer affordance and a listener never receives it.
                    .accessibilityLabel("Resume now")
            } else {
                // The kit's own menu, not SwiftUI's `Menu`: that renders a stock
                // AppKit menu -- grey slab, system corner radius, system highlight
                // -- which landed in the middle of the HUD looking like it belonged
                // to another application.
                AinkradMenuButton(items: SignalSnooze.allCases.map { snooze in
                    AinkradMenuItem(title: snooze.label, systemName: "bell.slash") {
                        onSnooze(snooze)
                    }
                }) {
                    quietGlyph
                }
                .help("Go quiet")
                .accessibilityLabel("Go quiet")
            }
            if unread > 0 {
                Button(action: onMarkAllRead) {
                    Text("Mark all read")
                        .font(AinkradFont.display(10, weight: .medium))
                        // Dimmed until pointed at, so the header reads as one
                        // title rather than two competing accents, and the
                        // control still answers when the pointer arrives.
                        .foregroundStyle(theme.accentPrimary
                            .opacity(hoveringMarkAll ? 1 : 0.72))
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : AinkradMotion.hover, value: hoveringMarkAll)
                .onHover { hoveringMarkAll = $0 }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Shared by the menu and the resume button so the two cannot drift apart
    /// visually while swapping in and out of the same slot.
    private var quietGlyph: some View {
        Image(systemName: isMuted ? "bell.slash.fill" : "bell.slash")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isMuted ? theme.accentSecondary
                                     : theme.foreground.opacity(0.45))
    }

    /// The hand-off. Chevron rather than an ellipsis: it goes somewhere.
    private var footer: some View {
        Button(action: onViewAll) {
            HStack(spacing: 5) {
                Text(events.count > Self.maxRows
                     ? "View all \(events.count) notifications"
                     : "View all notifications")
                    .font(AinkradFont.display(10.5, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    // The chevron alone leans the way it goes. Nudging the
                    // whole row instead would shift the label off the centre
                    // it shares with the header above it.
                    .offset(x: hoveringFooter && !reduceMotion ? 2 : 0)
            }
            .foregroundStyle(theme.accentPrimary.opacity(hoveringFooter ? 1 : 0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            // The tint ARRIVES rather than starting somewhere.
            //
            // This used to be a flat fill, under a comment insisting it was
            // "a tint band, not a separator line". It was both: a rectangle's
            // top edge is a hard horizontal rule across the full width of the
            // panel, which is precisely what the design language forbids, and
            // it was the one straight line in the whole surface. A gradient
            // that starts at nothing has no edge to read as a rule, and the
            // footer still separates itself from the last row.
            .background {
                LinearGradient(
                    colors: [.clear,
                             theme.surfaceElevated.opacity(hoveringFooter ? 0.85 : 0.55)],
                    startPoint: .top, endPoint: .bottom)
            }
            // Hover lights the accent from below instead of brightening the
            // slab, so the target answers without a second rectangle appearing.
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, theme.accentPrimary.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .opacity(hoveringFooter ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: hoveringFooter)
        .onHover { hoveringFooter = $0 }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "bell.slash")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(theme.foreground.opacity(0.3))
            Text("Nothing yet")
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
