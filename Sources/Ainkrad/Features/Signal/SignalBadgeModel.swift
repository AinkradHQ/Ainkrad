import Foundation
import Observation
import AinkradHostRuntime
import AinkradSignal

/// Per-app unread counts for launcher and dock badges.
///
/// A thin projection over `SignalCenter` rather than its own state: two
/// counters that can disagree is a bug waiting to be filed, and the center
/// already recomputes counts on every change.
@MainActor
@Observable
final class SignalBadgeModel {
    private let center: SignalCenter

    init(center: SignalCenter) { self.center = center }

    /// Unread events this app emitted. Host and Sage events are deliberately
    /// excluded — they belong to the bell, not to any app's icon.
    func count(for appID: String) -> Int {
        center.unreadCount(for: .app(appID: appID))
    }

    /// Capped at "99+": a launcher tile is a fixed size, and a four-digit count
    /// either clips or pushes its neighbours.
    static func badgeText(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case ...99: return String(count)
        default: return "99+"
        }
    }
}

/// Routes a tapped feed action back to the app that published it, confirming
/// first when the action declared itself destructive.
///
/// Shared by the dropdown and the overlay so both behave identically — an
/// action that asks for confirmation in one surface and not the other is worse
/// than one that never asks.
@MainActor
struct SignalActionRouter {
    let hub: SignalEmitterHub

    /// Returns the action to confirm, or nil when it was safe to run and has
    /// already been dispatched.
    @discardableResult
    func invoke(_ event: SignalEvent, _ action: SignalAction) -> SignalAction? {
        guard !action.isDestructive else { return action }
        dispatch(event, action)
        return nil
    }

    func dispatch(_ event: SignalEvent, _ action: SignalAction) {
        // Only an app-sourced event can carry an app action; a host event's
        // actions are the host's own concern and are not routed through the hub.
        guard case .app(let appID) = event.source else { return }
        Task { await hub.invoke(actionID: action.id, appID: appID) }
    }
}
