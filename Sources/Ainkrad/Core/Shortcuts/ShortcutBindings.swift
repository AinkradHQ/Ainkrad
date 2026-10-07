import AinkradHostRuntime
import AppKit

/// The persisted rebinding document: only the actions the user has changed
/// from their factory default are stored, keyed by `ShortcutAction.rawValue`.
/// Decoding tolerates an empty/legacy payload — a missing or unrecognized
/// `overrides` key simply means "no overrides yet". See AIN-144.
struct ShortcutBindings: PersistableDocument {
    static let documentID = "shortcut-bindings"

    var overrides: [String: KeyChord]

    init(overrides: [String: KeyChord] = [:]) {
        self.overrides = overrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try container.decodeIfPresent([String: KeyChord].self, forKey: .overrides) ?? [:]
    }

    /// The effective chord for `action` — its override if rebound, otherwise
    /// its factory default.
    func chord(for action: ShortcutAction) -> KeyChord {
        overrides[action.rawValue] ?? action.defaultChord
    }

    /// The testable core: the first action (in declaration order) whose
    /// effective chord matches the given key code + modifiers, or `nil`.
    func action(matching keyCode: UInt16, command: Bool, shift: Bool, option: Bool, control: Bool) -> ShortcutAction? {
        ShortcutAction.allCases.first {
            chord(for: $0).matches(keyCode: keyCode, command: command, shift: shift, option: option, control: control)
        }
    }

    /// Convenience overload for the monitor.
    func action(matching event: NSEvent) -> ShortcutAction? {
        action(
            matching: event.keyCode,
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
    }

    /// The other action already bound to `chord`, if any — used to reject a
    /// rebind that would collide.
    func conflict(of chord: KeyChord, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self.chord(for: $0) == chord }
    }

    private enum CodingKeys: String, CodingKey {
        case overrides
    }
}
