import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Positions `SignalBellDropdown` under the bell and dismisses it on an
/// outside click.
///
/// No scrim tint: a dropdown is not a modal, and dimming the workspace behind
/// a five-row glance would read as one. The catcher is transparent and exists
/// only to take the outside click.
struct SignalBellDropdownOverlay: View {
    let center: SignalCenter
    var hub: SignalEmitterHub?
    let onDismiss: () -> Void
    let onViewAll: () -> Void

    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            SignalBellDropdown(
                events: center.recent,
                unread: center.totalUnread,
                repeatCounts: center.repeatCounts,
                readIDs: center.readIDs,
                onActivate: { event in
                    center.activate(event)
                    onDismiss()
                },
                onAction: { event, action in
                    // The dropdown has no room for a confirmation dialog, so a
                    // destructive action hands off to the overlay rather than
                    // firing unconfirmed.
                    guard let hub else { return }
                    if SignalActionRouter(hub: hub).invoke(event, action) != nil { onViewAll() }
                },
                onMarkAllRead: { center.markAllRead(filter: .all) },
                onViewAll: onViewAll,
                isMuted: center.rules.suppression.isSuppressing(at: Date()),
                // A snooze set here is the same field quiet hours use, so the
                // two cannot disagree about whether now is quiet.
                onSnooze: { $0.apply(to: &center.rules.suppression, at: Date()) },
                onResume: { SignalSnooze.lift(&center.rules.suppression) })
                // Derived from the bar's own height rather than a copy of it.
                //
                // Deliberately NOT an NSPopover, despite reading like one.
                // `SignalBellButton`'s note explains why the bell lives
                // in-window: the first-run setup gate is a full-screen scrim
                // INSIDE the window, so anything in-window is covered for
                // free. A popover is a separate window and would escape it,
                // reintroducing exactly the escape-the-gate problem the old
                // menu-bar status item had to suppress by hand.
                .padding(.top, HUDBar.height + 4)
                .padding(.trailing, 10)
                // Reduce-motion drops the slide but keeps the fade: appearing
                // and disappearing with no change at all is a worse outcome
                // than a short one, because the panel then seems to teleport.
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
        }
        .ignoresSafeArea()
        // Escape closes it. Outside-click alone meant a keyboard user could
        // open the dropdown and have no way to put it away.
        .onExitCommand(perform: onDismiss)
    }
}
