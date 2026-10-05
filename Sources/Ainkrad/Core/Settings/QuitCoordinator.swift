import AinkradHostRuntime
import AppKit
import Observation

/// Drives the in-app quit confirmation HUD around `NSApplication`'s
/// `applicationShouldTerminate(_:)` / `.terminateLater` flow. The app
/// delegate calls `requestTerminate()` synchronously from
/// `applicationShouldTerminate(_:)`; when it returns `.terminateLater`,
/// `isConfirming` drives the HUD and `confirm`/`cancel` later deliver the
/// deferred reply via `terminator`.
@MainActor
@Observable
final class QuitCoordinator {
    private(set) var isConfirming = false
    private let persistence: PersistenceStore
    private let terminator: TerminationReplying

    init(persistence: PersistenceStore, terminator: TerminationReplying) {
        self.persistence = persistence
        self.terminator = terminator
    }

    /// Called from `applicationShouldTerminate(_:)`. Skips confirmation (and
    /// terminates immediately) when the user has turned it off; otherwise
    /// shows the HUD and defers the reply.
    func requestTerminate() -> NSApplication.TerminateReply {
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        guard settings.confirmBeforeQuit else { return .terminateNow }
        isConfirming = true
        return .terminateLater
    }

    /// The user confirmed quitting from the HUD. `dontAskAgain` persists the
    /// preference (preserving the rest of `GlobalSettings`) so future quits
    /// skip the confirmation.
    func confirm(dontAskAgain: Bool) {
        if dontAskAgain {
            var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
            settings.confirmBeforeQuit = false
            persistence.save(settings)
        }
        isConfirming = false
        terminator.reply(true)
    }

    /// The user cancelled from the HUD — the app keeps running.
    func cancel() {
        isConfirming = false
        terminator.reply(false)
    }
}
