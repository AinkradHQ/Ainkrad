import AppKit
import SwiftUI

/// One ⌥-chord: which physical key, and what it does.
///
/// Matching is by `keyCode`, never by character — ⌥F produces "ƒ" and ⌥A
/// produces "å", so character matching would silently fail exactly the way the
/// first SwiftUI attempt at ⌘⇧F did.
struct HoardOptionChord {
    /// `kVK_ANSI_*`. Layout-independent, unlike the produced character.
    let keyCode: UInt16
    let action: () -> Void

    static let f: UInt16 = 3
    static let r: UInt16 = 15
    static let a: UInt16 = 0
    static let e: UInt16 = 14
}

/// Local `keyDown` monitor for Hoard' ⌥-chorded shortcuts.
///
/// Follows `ComposerTabCycleMonitor`'s established pattern rather than
/// SwiftUI's `.onKeyPress`, which only fires while its container holds focus —
/// unreliable in a pane where the caret may be in the list, the breadcrumb or
/// a field. A local monitor sees the event whoever has focus.
///
/// **⌥, not ⌘⇧.** The original ⌘⇧F never reached the app even through this
/// monitor, which means it is claimed above us — a local monitor runs before
/// the app's own responder chain but AFTER system-level bindings, so anything
/// macOS or another app has taken is simply invisible here. The ⌥ layer is
/// unclaimed, so every Hoard chord that needs to work regardless of focus
/// lives here.
struct HoardKeyMonitor: NSViewRepresentable {
    let chords: [HoardOptionChord]

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.chords = chords
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.chords = chords
    }

    static func dismantleNSView(_ nsView: MonitoringView, coordinator: ()) {
        nsView.teardown()
    }

    final class MonitoringView: NSView {
        var chords: [HoardOptionChord] = []
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    // EXACTLY option — ⌘F (global palette) and every other
                    // chord must keep passing through untouched.
                    guard flags == .option,
                        let chord = self.chords.first(where: { $0.keyCode == event.keyCode })
                    else { return event }
                    chord.action()
                    return nil  // swallow, so it doesn't also beep
                }
            } else {
                teardown()
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        // No `deinit` cleanup: the monitor is `Any?`, which is not `Sendable`,
        // and Swift 6 forbids touching it from a nonisolated `deinit`.
        // `viewDidMoveToWindow(nil)` and `dismantleNSView` both call
        // `teardown()`, which covers every real removal path.
    }
}
