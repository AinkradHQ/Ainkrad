import AinkradHostRuntime
import AppKit
import WebKit

/// FD36: a plugin in the focused pane outranks the host for the chords it
/// claims. Forge's ⌘W (close tab), ⌘1/⌘2 (focus editor pane) and ⌘⇧P
/// (command palette) never fired because `KeyboardShortcutMonitor` consumed
/// them first as Close Block, jump to workspace and Cycle Permission Mode.
///
/// Plugins claim a chord with a zero-size SwiftUI `.keyboardShortcut` button
/// (Forge's `ShortcutLayer`, `LoreCommandShortcuts`, Grimoire's claims).
/// Those buttons are dispatched from `performKeyEquivalent`, so before the
/// host acts on one of its chords it offers the event there; only when no
/// claim answers does the host act as it always did.
///
/// ## Why the window, not the pane's subtree
///
/// A plugin's root view is inline SwiftUI inside the host's one hosting view
/// (`PaneContent` puts the `AnyView` straight in), so a pane has no `NSView`
/// subtree that holds its SwiftUI shortcuts — they live in the window's
/// hosting view. Offering the event there reaches every mounted claim, so a
/// plugin should mount its claims only while `ainkradPaneIsFocused`.
@MainActor
enum PluginKeyClaim {
    /// Whether to offer a key event to the plugins before the host acts on it.
    ///
    /// - Only host chords: everything else already reaches the plugins through
    ///   the normal key-equivalent path, untouched.
    /// - Never push-to-talk: it is a hold gesture with its own key-up edge.
    /// - Never while a host overlay is up (Launcher, Settings, Overview, App
    ///   Store, Quick Ask, setup, the quit HUD): the overlay owns the keyboard
    ///   and ⌘K / ⌘, must keep closing it.
    /// - Only when the focused pane hosts a plugin; built-in apps never claim.
    /// - Never while a web view has the keyboard: `WKWebView` answers YES to
    ///   every key equivalent it holds focus for and hands it to the page, so
    ///   ⌘← or ⌘D would turn into editing commands instead of host chords.
    static func offers(
        isHostChord: Bool,
        isPushToTalk: Bool,
        isOverlayPresented: Bool,
        focusedPaneIsPlugin: Bool,
        webViewHasKeyboard: Bool
    ) -> Bool {
        isHostChord && !isPushToTalk && !isOverlayPresented && focusedPaneIsPlugin && !webViewHasKeyboard
    }

    /// The monitor's entry point: true when a plugin claim took `event`, so
    /// the host must not act on it.
    static func takes(
        _ event: NSEvent, isHostChord: Bool, action: ShortcutAction?, in environment: AppEnvironment, window: NSWindow?
    ) -> Bool {
        offers(
            isHostChord: isHostChord,
            isPushToTalk: action == .pushToTalk,
            isOverlayPresented: environment.isSetupPresented || environment.isLauncherPresented
                || environment.isWorkspaceOverviewPresented || environment.isSettingsPresented
                || environment.isAppStorePresented || environment.isQuickAskPresented
                || environment.quitCoordinator.isConfirming,
            focusedPaneIsPlugin: focusedPaneIsPlugin(in: environment),
            webViewHasKeyboard: webViewHasKeyboard(in: window)
        ) && claim(event, in: window)
    }

    static func focusedPaneIsPlugin(in environment: AppEnvironment) -> Bool {
        let layout = environment.workspaceManager.activeWorkspace.tileLayout
        guard let focusedID = layout.focusedBlockID,
            let appID = layout.blocks.first(where: { $0.id == focusedID })?.appID,
            case .plugin = environment.registry.allApps.first(where: { $0.id == appID })?.source
        else { return false }
        return true
    }

    /// Offers `event` to the window's key-equivalent claims. True when one took
    /// it (the claim has already run).
    static func claim(_ event: NSEvent, in window: NSWindow?) -> Bool {
        window?.contentView?.performKeyEquivalent(with: event) ?? false
    }

    /// Whether the first responder is, or sits inside, a `WKWebView`.
    static func webViewHasKeyboard(in window: NSWindow?) -> Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }
}
