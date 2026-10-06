import AppKit
import SwiftUI

/// Hands the window's keyboard focus to the app inside a pane the moment that
/// pane becomes the focused one.
///
/// Why this exists: with the pane header gone, Focus Mode's tab strip is the
/// way to switch panes — and clicking a tab used to only move the host's
/// `focusedBlockID`. The pane came forward looking active (brackets, glow)
/// while the keystrokes still went wherever they went before, so switching to a
/// terminal tab and typing did nothing until you clicked into it. Focus that
/// isn't keyboard focus is a lie the UI tells.
///
/// ## How it finds the app's view — and why not by walking the view tree
///
/// The host can't name the plugin's view; it doesn't know what's inside a pane.
/// The first attempt searched the AppKit hierarchy around a zero-size anchor
/// planted in the pane, and it worked only intermittently. Logging the live
/// tree showed why, and the reason is structural, not a tuning problem:
/// SwiftUI hosts every `NSViewRepresentable` in its own backing layer, so the
/// anchor's subtree never contained the terminal at all — and the depth at
/// which panes became siblings *changed between runs of the same build*.
/// SwiftUI's backing hierarchy is an implementation detail; no amount of
/// climbing or scoping makes it a reliable index.
///
/// So this asks AppKit the question AppKit actually answers: **what visible,
/// interactive view is at this point?** `hitTest` is exactly that, and it
/// already accounts for the thing that makes Focus Mode hard — every pane sits
/// at full canvas size, stacked, and only the focused one is visible and
/// hit-testable (the others are `opacity 0` with hit testing off). So a hit
/// test at the pane's center lands inside the focused pane by construction,
/// with no geometry comparison and no assumptions about tree shape.
struct PaneKeyFocusAnchor: NSViewRepresentable {
    let isFocused: Bool

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isFocusedPane = isFocused
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        let wasFocused = nsView.isFocusedPane
        nsView.isFocusedPane = isFocused
        // Only on the false → true transition. Claiming the keyboard on every
        // render would fight the user: it would yank focus out of the Launcher
        // field or a tab being renamed on each unrelated redraw.
        guard isFocused, !wasFocused else { return }
        nsView.beginClaimingKeyboard()
    }

    /// A zero-cost marker filling the pane (it is installed as the pane's
    /// background, so its bounds ARE the pane's bounds — that is all the
    /// geometry the hit test needs).
    final class AnchorView: NSView {
        var isFocusedPane = false

        /// Retry schedule, in seconds, walked sequentially and stopping at the
        /// first success.
        ///
        /// The first delay must clear TWO things, and both of them cost
        /// correctness or smoothness when it doesn't:
        ///
        /// 1. **The frame that reveals the pane.** Making a terminal first
        ///    responder costs ~8ms (it redraws) and revealing the pane costs
        ///    ~10ms; in one frame that blows the 16.7ms budget and drops a frame
        ///    on every switch. Measured: 18ms median stall → 1.0ms, against a
        ///    0.9ms idle floor.
        /// 2. **Ambiguity about which pane it is.** This used to have to wait out
        ///    a 170ms content cross-fade, during which BOTH panes were partly
        ///    visible and still hit-testable, so the hit test could land in the
        ///    wrong pane — and the pane at the bottom of the stack, the first
        ///    tab, was the one that systematically lost. That was the "focus
        ///    works on every tab except the first" bug.
        ///
        ///    The cross-fade is gone (it was also what flashed), the focused pane
        ///    now sits on top via `zIndex`, and the claim refuses a target that
        ///    isn't visible. With all three, there is no fade left to wait out,
        ///    so this only has to clear the reveal frame.
        private static let retryDelays: [TimeInterval] = [0.06, 0.12, 0.22, 0.4]

        /// The live retry chain. A new claim cancels the previous one, so a
        /// stale chain cannot fire and steal the keyboard back; each attempt
        /// also re-checks that the pane is still the focused one.
        private var claimTask: Task<Void, Never>?
        private var isAwaitingKeyWindow = false

        /// The focused pane should own the keyboard from the moment it appears,
        /// not only after a switch — so claim on mount too.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, isFocusedPane else { return }
            beginClaimingKeyboard()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            stopAwaitingKeyWindow()
        }

        func beginClaimingKeyboard() {
            claimTask?.cancel()
            claimTask = Task { @MainActor [weak self] in
                for delay in Self.retryDelays {
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self, self.isFocusedPane else { return }
                    if self.claimKeyboard() { return }
                }
            }
        }

        /// Returns true once the keyboard is inside this pane, so later retries
        /// become no-ops.
        @discardableResult
        private func claimKeyboard() -> Bool {
            guard let window, let contentView = window.contentView else { return false }
            // At launch the window becomes key only after the panes mount. Wait
            // for it rather than dropping the claim, or the focused pane starts
            // life without the keyboard.
            guard window.isKeyWindow else {
                awaitKeyWindow(window)
                return false
            }
            // Already where we put it last time — the cheap path, and the one
            // every repeat claim takes.
            // A live text field owns the keyboard for a reason (Launcher search,
            // a tab mid-rename, a settings field). Never take it from one.
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return false }
            // The pane must be big enough to aim at — a pane mid-layout at zero
            // size would hit-test into whatever is behind it.
            guard bounds.width > 8, bounds.height > 8 else { return false }

            let centerInContent = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: contentView)
            guard let hit = contentView.hitTest(centerInContent) else { return false }
            // Belt and braces on top of the timing: refuse a view that is not
            // actually on screen. If a cross-fade is still running, or another
            // workspace's pane is somehow the hit, this fails and the next retry
            // tries again rather than handing the keyboard to an invisible
            // terminal — which the user would experience as typing into nothing.
            guard Self.isEffectivelyVisible(hit, upTo: contentView) else { return false }
            guard let target = Self.responderTarget(from: hit) else { return false }
            // Already there — don't disturb exactly where inside the pane.
            if window.firstResponder as? NSView === target { return true }
            return window.makeFirstResponder(target)
        }

        /// The nearest view at or above the hit view that will take the
        /// keyboard. Climbing UP from the hit is safe in a way that climbing
        /// blind was not: the hit view is already known to be inside the
        /// focused pane, and a container that accepts first responder on behalf
        /// of its content (scroll views, representable hosts) is the right
        /// target anyway.
        private static func responderTarget(from hit: NSView) -> NSView? {
            var candidate: NSView? = hit
            while let view = candidate {
                if view.acceptsFirstResponder, view.canBecomeKeyView { return view }
                candidate = view.superview
            }
            return nil
        }

        /// Whether `view` is really visible: nothing between it and `root` is
        /// hidden or faded out. SwiftUI expresses `.opacity()` on a hosted
        /// AppKit view as a layer opacity, so both that and `isHidden` have to
        /// be checked, all the way up.
        private static func isEffectivelyVisible(_ view: NSView, upTo root: NSView) -> Bool {
            var current: NSView? = view
            while let node = current {
                if node.isHidden { return false }
                if node.alphaValue < 0.9 { return false }
                if let opacity = node.layer?.opacity, opacity < 0.9 { return false }
                if node === root { return true }
                current = node.superview
            }
            return true
        }

        /// Re-runs the claim once the window becomes key. Selector-based (not
        /// block-based) observation so it can be torn down from
        /// `viewWillMove(toWindow:)` rather than from a `deinit` that isn't
        /// allowed to touch non-Sendable state.
        private func awaitKeyWindow(_ window: NSWindow) {
            guard !isAwaitingKeyWindow else { return }
            isAwaitingKeyWindow = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }

        private func stopAwaitingKeyWindow() {
            guard isAwaitingKeyWindow else { return }
            isAwaitingKeyWindow = false
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            stopAwaitingKeyWindow()
            guard isFocusedPane else { return }
            beginClaimingKeyboard()
        }
    }
}
