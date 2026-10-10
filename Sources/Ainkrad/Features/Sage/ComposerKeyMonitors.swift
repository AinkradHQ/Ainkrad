import AppKit
import SwiftUI

/// Local `keyDown` monitor used by `SageComposerBar` (M7 finalize Wave D,
/// D2 — extracted verbatim, no behavior change). App-scoped (not global),
/// mirroring `KeyboardShortcutMonitor`'s established pattern.

/// Installs a local `keyDown` monitor that swallows a plain Tab OR Shift+Tab
/// keystroke to cycle the active agent, ONLY while the composer's draft is
/// empty — otherwise Tab is returned untouched so it keeps moving keyboard
/// focus everywhere else (M7 Slice 5a Task 5; Shift+Tab added Wave 3c so the
/// agent icon button's tooltip hint has a matching keystroke). A Tab held
/// with any OTHER modifier (cmd/opt/ctrl) always passes through. Zero-size,
/// invisible; attached via `.background(...)` so it rides the composer's
/// lifetime.
struct ComposerTabCycleMonitor: NSViewRepresentable {
    let isDraftEmpty: () -> Bool
    let onCycle: () -> Void

    /// Tab (keyCode 48) with no modifiers, or with ONLY Shift — any other
    /// modifier combo (cmd/opt/ctrl) passes through untouched. Pure so the key
    /// table is testable without a window.
    nonisolated static func isCycleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return keyCode == 48 && (flags.isEmpty || flags == .shift)
    }

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.isDraftEmpty = isDraftEmpty
        view.onCycle = onCycle
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.isDraftEmpty = isDraftEmpty
        nsView.onCycle = onCycle
    }

    final class MonitoringView: NSView {
        var isDraftEmpty: (() -> Bool)?
        var onCycle: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    if ComposerTabCycleMonitor.isCycleKey(keyCode: event.keyCode, modifiers: event.modifierFlags),
                        self.isDraftEmpty?() == true
                    {
                        self.onCycle?()
                        return nil
                    }
                    return event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
