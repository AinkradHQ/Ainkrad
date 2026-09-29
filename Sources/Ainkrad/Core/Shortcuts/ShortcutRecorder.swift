import AppKit
import Observation

/// Captures the next key-down event as a `KeyChord` and applies it via
/// `ShortcutStore.rebind`, surfacing a conflict message if it collides with
/// another action. A reference type so the local `NSEvent` monitor's
/// completion closure mutates shared, observable state rather than a
/// snapshot of a value-type view.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var action: ShortcutAction?
    private(set) var conflictMessage: String?
    private var monitor: Any?
    private var store: ShortcutStore?

    func start(_ action: ShortcutAction, store: ShortcutStore) {
        stop()
        conflictMessage = nil
        self.action = action
        self.store = store
        // Suppress the always-on KeyboardShortcutMonitor for the duration of
        // the recording so it can't act on the chord being captured (AIN-144).
        store.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {   // Esc cancels the recording without rebinding.
                self.stop()
                return nil
            }
            let chord = KeyChord(
                keyCode: event.keyCode,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control)
            )
            if store.rebind(action, to: chord) {
                self.conflictMessage = nil
            } else {
                let owner = store.bindings.conflict(of: chord, excluding: action)
                self.conflictMessage = "\(chord.displayString) is already used by \(owner?.displayName ?? "another shortcut")."
            }
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        action = nil
        // Always clear the suppression gate on the way out — captured,
        // cancelled (Esc), or the view disappearing all route through here —
        // so a stuck flag can never disable the always-on monitor (AIN-144).
        store?.isRecordingShortcut = false
        store = nil
    }
}
