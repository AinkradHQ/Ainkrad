import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI

/// App-presence queries and cross-app hand-offs on the composition root.
extension AppEnvironment {
    /// True when this app currently has a live shell, by EITHER presentation
    /// route: a tiled pane in any workspace, or the floating overlay
    /// (`.overlay` apps never get a `tileLayout` block — see the launch-hub
    /// open handler in `finalizeBootstrap`).
    ///
    /// This composition lives here because `AppEnvironment` is the only type
    /// that owns both halves. Backs the app-hosted MCP activator's "do I need
    /// to launch this app first?" check — answering `false` for an already-
    /// presented overlay app would make every tool call against it wait out the
    /// launch timeout and fail, for a server that was reachable the whole time.
    func isAppOpen(_ appID: String) -> Bool {
        workspaceManager.isAppTiled(appID) || presentedOverlayAppID == appID
    }

    /// Re-syncs the live `commandRegistry` with the current
    /// `skillCommandStore` bindings. Bootstrap (`bootstrap()` below) only
    /// registers skill `/name` commands once, at launch — a bind/unbind made
    /// afterward via the Skills manager UI (Task 13) would otherwise sit
    /// invisibly in `skillCommandStore` until the next relaunch. Call this
    /// after every bind/unbind so `/name` starts/stops working immediately.
    /// Never touches a builtin: it only unregisters names THIS method
    /// previously registered, then re-registers the current binding set
    /// (`slashCommands(registry:)` independently filters out any name that
    /// collides with a builtin, as defense in depth).
    func resyncSkillCommands() {
        for name in registeredSkillCommandNames {
            commandRegistry.unregister(name: name)
        }
        let commands = skillCommandStore.slashCommands(registry: skillRegistry)
        for command in commands {
            commandRegistry.register(command)
        }
        registeredSkillCommandNames = Set(commands.map(\.name))
    }

    /// Hand a markdown file to Lore, in basic mode.
    ///
    /// Goes through `PluginLaunchHub` rather than opening a pane directly, so
    /// Hoard gets the same availability check a plugin would: Lore may be
    /// uninstalled or switched off.
    ///
    /// Returns why it could not be opened, or nil on success, so the CALLER
    /// surfaces it. Hoard's toast lives on the pane and this does not — and a
    /// failure that is only logged is the "recorded, never surfaced" shape this
    /// codebase has been bitten by before (Leyline's Connect button).
    ///
    /// `mode: .basic` is stated rather than left to Lore's setting on purpose —
    /// the whole point of clicking a `.md` is to see THAT file, not to arrive
    /// in the vault browser.
    @discardableResult
    @MainActor
    func openDocumentInLore(_ url: URL) -> String? {
        let intent = AinkradLaunchIntent(path: url.path, mode: .basic)
        guard let payload = intent.json else { return "That path couldn't be encoded." }
        switch pluginLaunchHub.availability(of: "lore") {
        case .available:
            pluginLaunchHub.enqueue(target: "lore", payload: payload)
            pluginLaunchHub.requestOpen("lore")
            return nil
        case .disabled:
            return "Lore is disabled — enable it in the App Store."
        case .unknown:
            return "Lore isn't installed — install it from the App Store."
        }
    }
}
