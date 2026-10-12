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
    /// The HUD's "Don't ask again" box. Here rather than in the view so Return from the key monitor
    /// (which works wherever focus is) quits with the same answer as the Quit button.
    var dontAskAgain = false
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
        dontAskAgain = false
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

    /// Return / keypad Enter quits (with the HUD's "Don't ask again"), Esc cancels — answered from the key
    /// monitor, so they work while a plugin's text view holds focus. `false` = not confirming, or another key.
    func answer(keyCode: UInt16, beforeQuit: () -> Void) -> Bool {
        guard isConfirming else { return false }
        switch keyCode {
        case SetupGate.returnKey, SetupGate.keypadEnter:
            beforeQuit()
            confirm(dontAskAgain: dontAskAgain)
        case SetupGate.escape: cancel()
        default: return false
        }
        return true
    }

    /// The user cancelled from the HUD — the app keeps running.
    func cancel() {
        isConfirming = false
        terminator.reply(false)
    }
}
