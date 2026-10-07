import AppKit
import SwiftUI

/// Local `keyDown` monitors used by `SageComposerBar` (M7 finalize Wave D,
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

/// Local `keyDown` monitor (same app-scoped pattern as `ComposerTabCycleMonitor`)
/// that swallows Up/Down/Return while the palette or mention overlay is visible,
/// driving list navigation/confirmation — the overlays themselves have no text
/// field of their own to receive these keys, since their query comes from the
/// composer's own draft. Esc is deliberately NOT handled here:
/// `.ainkradFloatingPanel` already dismisses on Esc via its own monitor.
struct ComposerOverlayKeyMonitor: NSViewRepresentable {
    let isActive: () -> Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onConfirm: () -> Void

    /// The overlay keys this monitor swallows.
    enum Key: Equatable { case up, down, confirm }

    /// Up arrow (126), Down arrow (125), Return (36) / keypad Enter (76); every
    /// other key passes through. Pure so the key table is testable.
    nonisolated static func key(for keyCode: UInt16) -> Key? {
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 36, 76: return .confirm
        default: return nil
        }
    }

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.isActive = isActive
        view.onUp = onUp
        view.onDown = onDown
        view.onConfirm = onConfirm
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.isActive = isActive
        nsView.onUp = onUp
        nsView.onDown = onDown
        nsView.onConfirm = onConfirm
    }

    final class MonitoringView: NSView {
        var isActive: (() -> Bool)?
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onConfirm: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.isActive?() == true else { return event }
                    switch ComposerOverlayKeyMonitor.key(for: event.keyCode) {
                    case .up: self.onUp?()
                    case .down: self.onDown?()
                    case .confirm: self.onConfirm?()
                    case nil: return event
                    }
                    return nil
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
