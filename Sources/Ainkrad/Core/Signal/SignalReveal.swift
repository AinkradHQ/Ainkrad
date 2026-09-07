import Foundation

/// One workspace's panes, as much as revealing needs to know.
struct SignalRevealWorkspace: Equatable {
    let id: UUID
    /// `(appID, blockID)` for every pane in this workspace, in layout order.
    let panes: [Pane]

    struct Pane: Equatable {
        let appID: String
        let blockID: UUID
        /// What this pane last reported through `ainkradPaneLocator`, if the
        /// app reports at all. Nil for every app that does not — which is most
        /// of them, and which is why locator matching can only ever be a
        /// preference and never a requirement.
        let locator: String?
        init(appID: String, blockID: UUID, locator: String? = nil) {
            self.appID = appID
            self.blockID = blockID
            self.locator = locator
        }
    }
}

/// What the host should do to show the app a notification came from.
enum SignalRevealAction: Equatable {
    /// The app is already on screen: focus its pane, switching workspace first
    /// when it lives on another one.
    case focus(workspaceID: UUID, blockID: UUID)
    /// The app presents as a floating overlay rather than a pane.
    case presentOverlay
    /// Not open anywhere — open it.
    case openNewPane

    /// Whether the host should hand the deep link's payload to the app.
    ///
    /// **False for `.focus`, and that is the point.** `PluginLaunchHub` holds
    /// one pending payload per app and `takePendingLaunch()` is a pull consumed
    /// once, at pane creation — so a pane that already exists never collects
    /// it. Enqueuing anyway left the payload sitting in the mailbox until the
    /// next pane of that app was created, where it arrived as the launch
    /// payload for a session it had nothing to do with, and in the meantime
    /// overwrote any legitimate pending launch (the hub is one slot, not a
    /// queue).
    ///
    /// Not a security hole — Rune's `SSHLaunchPayload.pending(from:)`
    /// JSON-decodes and returns nil for a Signal payload, so the pane opens a
    /// plain terminal — but it is a payload delivered to the wrong place at the
    /// wrong time, which is worse than one not delivered at all.
    ///
    /// Delivering it to the RIGHT pane is a separate, larger problem: the host
    /// cannot know which pane holds which session without a per-pane locator on
    /// the plugin contract. Until that exists, declining to deliver is the
    /// honest behaviour.
    var deliversPayload: Bool {
        switch self {
        case .focus: return false
        case .presentOverlay, .openNewPane: return true
        }
    }
}

enum SignalReveal {
    /// Decides how to reveal `appID`.
    ///
    /// **Focusing an existing pane, not opening another one.** `openApp(_:)`
    /// unconditionally appends a new `Block`, so following a deep link through
    /// it gave the user a second, empty terminal instead of the session that
    /// called them — the notification took them further from the thing it was
    /// about.
    ///
    /// The active workspace is searched first: when a pane exists both here and
    /// elsewhere, yanking the user to another workspace would be a bigger
    /// disruption than the notification is worth.
    /// `locator` is the deep link's `SignalDeepLink.locator`: the app's own
    /// name for the thing the notification is about — a terminal session id, a
    /// document path. When a pane reports the same value, that pane is the one
    /// the notification meant, and focusing any other pane of the app sends
    /// the user to the wrong place while looking like it worked.
    ///
    /// Locator matching is a PREFERENCE, never a requirement: most apps report
    /// nothing, a pane may not have reported yet, and the pane that held a
    /// session may have closed. Every one of those falls through to the
    /// app-level behaviour that shipped in generation 9, which is right rather
    /// than merely tolerable — being taken to the app is a good outcome, being
    /// taken nowhere is not.
    static func action(appID: String,
                       presentsAsOverlay: Bool,
                       workspaces: [SignalRevealWorkspace],
                       activeWorkspaceID: UUID,
                       locator: String? = nil) -> SignalRevealAction {
        if presentsAsOverlay { return .presentOverlay }

        // Ordered active-first at BOTH precedence levels, because a locator
        // match on another workspace should still beat a bare app match here
        // — the point of a locator is that one specific pane is the right
        // answer — while an unnecessary workspace switch stays the thing we
        // avoid when nothing distinguishes the candidates.
        let ordered = [workspaces.first { $0.id == activeWorkspaceID }].compactMap { $0 }
            + workspaces.filter { $0.id != activeWorkspaceID }

        if let locator, !locator.isEmpty {
            for workspace in ordered {
                if let pane = workspace.panes.first(where: {
                    $0.appID == appID && $0.locator == locator
                }) {
                    return .focus(workspaceID: workspace.id, blockID: pane.blockID)
                }
            }
        }

        for workspace in ordered {
            if let pane = workspace.panes.first(where: { $0.appID == appID }) {
                return .focus(workspaceID: workspace.id, blockID: pane.blockID)
            }
        }
        return .openNewPane
    }
}
