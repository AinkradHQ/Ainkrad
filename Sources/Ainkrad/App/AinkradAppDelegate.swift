import AppKit
import UserNotifications

/// The app is otherwise pure SwiftUI (no other `NSApplicationDelegate`
/// responsibilities) — this exists solely to intercept termination. ⌘Q, the
/// app menu's Quit, and the Dock's Quit all route through
/// `NSApp.terminate(_:)`, which calls `applicationShouldTerminate(_:)` here
/// before the app actually dies.
@MainActor
final class AinkradAppDelegate: NSObject, NSApplicationDelegate {
    /// Wired from `AinkradHostApp.init` right after `AppEnvironment`
    /// bootstraps. `applicationShouldTerminate(_:)` can in principle fire
    /// before that (e.g. a very early Dock quit) — the fallback below just
    /// lets the app quit rather than hanging with no coordinator to reply.
    var quitCoordinator: QuitCoordinator?
    /// Wired from `AinkradHostApp.init` alongside `quitCoordinator`. Owns the
    /// `NSStatusItem`/popover for the app's lifetime — installed here on
    /// launch, torn down on quit (M7 Slice 7).
    var menuBarController: MenuBarController?
    /// Wired alongside the above. Chat-history writes are coalesced (see
    /// `SageSessionStore.syncActive`), so the last few hundred
    /// milliseconds of a transcript may still be pending when the user quits —
    /// this is where that gets forced to disk.
    var assistantSessionStore: SageSessionStore?
    /// Wired alongside the above. Owns the external-ingress socket's lifetime
    /// from the AppKit side: nothing else gets a `willTerminate` callback.
    var signalSocketServer: SignalSocketServer?
    /// Wired alongside the above. MUST outlive every banner:
    /// `UNUserNotificationCenter.delegate` is a WEAK reference, so with nothing
    /// else holding the responder, banner clicks would silently stop working
    /// the moment it was deallocated.
    var signalBannerResponder: SignalBannerResponder?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitCoordinator?.requestTerminate() ?? .terminateNow
    }

    // Cardinal HUD is a dark-only design language — force dark appearance
    // regardless of the macOS system setting so traffic-lights, native
    // NSVisualEffectView materials, and any other AppKit-owned chrome
    // always render dark.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Before anything can post. macOS delivers a response to whatever
        // delegate is registered at the time, so a delegate installed later
        // means the first click of the session goes nowhere and reports nothing.
        if let signalBannerResponder {
            UNUserNotificationCenter.current().delegate = signalBannerResponder
        }
        menuBarController?.install()
        LaunchSignpost.end()
    }

    func applicationWillTerminate(_ notification: Notification) {
        assistantSessionStore?.flush()
        // Unlink the ingress socket on the way out. `start()` also unlinks a
        // stale path, so a crash is survivable either way — but leaving a live
        // socket file behind means anything that connects between quit and the
        // next launch writes into nothing and is told it succeeded.
        signalSocketServer?.stop()
        menuBarController?.teardown()
    }
}
