import AinkradHostRuntime
import Observation

/// Owns the user's shortcut rebindings: loads `ShortcutBindings` from
/// persistence, exposes the effective chord for each action, and applies
/// rebinds (rejecting ones that would conflict with another action). Read by
/// both the Settings UI and `KeyboardShortcutMonitor`. See AIN-144.
@MainActor
@Observable
final class ShortcutStore {
    private(set) var bindings: ShortcutBindings
    private let persistence: PersistenceStore

    /// Set by `ShortcutRecorder` while it is capturing a chord. The
    /// always-on `KeyboardShortcutMonitor` checks this first and passes
    /// every key event through untouched while it's `true`, so recording a
    /// chord that happens to match another action's binding can't also
    /// trigger that action's side effect (AIN-144).
    var isRecordingShortcut: Bool = false

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.bindings = persistence.load(ShortcutBindings.self) ?? ShortcutBindings()
    }

    func chord(for action: ShortcutAction) -> KeyChord {
        bindings.chord(for: action)
    }

    /// Rebinds `action` to `chord`, persisting the change. Returns `false`
    /// (and leaves bindings untouched) if `chord` already belongs to another
    /// action.
    @discardableResult
    func rebind(_ action: ShortcutAction, to chord: KeyChord) -> Bool {
        guard bindings.conflict(of: chord, excluding: action) == nil else { return false }
        bindings.overrides[action.rawValue] = chord
        persistence.save(bindings)
        return true
    }

    func resetToDefault(_ action: ShortcutAction) {
        bindings.overrides.removeValue(forKey: action.rawValue)
        persistence.save(bindings)
    }

    func resetToDefaults() {
        bindings.overrides.removeAll()
        persistence.save(bindings)
    }
}
