import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("KeyChord")
struct KeyChordTests {
    @Test("matches true when keyCode + all four modifiers agree")
    func matchesTrue() {
        let chord = KeyChord(keyCode: 40, command: true, shift: false, option: false, control: false)
        #expect(chord.matches(keyCode: 40, command: true, shift: false, option: false, control: false))
    }

    @Test("matches false when a modifier disagrees")
    func matchesFalseModifier() {
        let chord = KeyChord(keyCode: 40, command: true, shift: false, option: false, control: false)
        #expect(!chord.matches(keyCode: 40, command: true, shift: true, option: false, control: false))
    }

    @Test("matches false when the keyCode disagrees")
    func matchesFalseKeyCode() {
        let chord = KeyChord(keyCode: 40, command: true, shift: false, option: false, control: false)
        #expect(!chord.matches(keyCode: 0, command: true, shift: false, option: false, control: false))
    }

    @Test("displayString renders ⌘K")
    func displayCmdK() {
        let chord = KeyChord(keyCode: 40, command: true, shift: false, option: false, control: false)
        #expect(chord.displayString == "⌘K")
    }

    @Test("displayString renders ⌘⇧A")
    func displayCmdShiftA() {
        let chord = KeyChord(keyCode: 0, command: true, shift: true, option: false, control: false)
        #expect(chord.displayString == "⌘⇧A")
    }

    @Test("displayString renders ⌥⇥")
    func displayOptionTab() {
        let chord = KeyChord(keyCode: 48, command: false, shift: false, option: true, control: false)
        #expect(chord.displayString == "⌥⇥")
    }
}

@Suite("ShortcutAction defaults")
struct ShortcutActionDefaultsTests {
    @Test("openLauncher defaults to ⌘K (keyCode 40)")
    func openLauncher() {
        #expect(
            ShortcutAction.openLauncher.defaultChord
                == KeyChord(keyCode: 40, command: true, shift: false, option: false, control: false))
    }

    @Test("toggleSettings defaults to ⌘, (keyCode 43)")
    func toggleSettings() {
        #expect(
            ShortcutAction.toggleSettings.defaultChord
                == KeyChord(keyCode: 43, command: true, shift: false, option: false, control: false))
    }

    @Test("toggleAppStore defaults to ⌘⇧A (keyCode 0)")
    func toggleAppStore() {
        #expect(
            ShortcutAction.toggleAppStore.defaultChord
                == KeyChord(keyCode: 0, command: true, shift: true, option: false, control: false))
    }

    @Test("newWorkspace defaults to ⌘⇧N (keyCode 45)")
    func newWorkspace() {
        #expect(
            ShortcutAction.newWorkspace.defaultChord
                == KeyChord(keyCode: 45, command: true, shift: true, option: false, control: false))
    }

    @Test("toggleWorkspaceOverview defaults to ⌥Tab (keyCode 48)")
    func toggleWorkspaceOverview() {
        #expect(
            ShortcutAction.toggleWorkspaceOverview.defaultChord
                == KeyChord(keyCode: 48, command: false, shift: false, option: true, control: false))
    }

    @Test("closeBlock defaults to ⌘W (keyCode 13)")
    func closeBlock() {
        #expect(
            ShortcutAction.closeBlock.defaultChord
                == KeyChord(keyCode: 13, command: true, shift: false, option: false, control: false))
    }

    @Test("openQuickAsk defaults to ⌘⇧Space (keyCode 49)")
    func openQuickAsk() {
        #expect(
            ShortcutAction.openQuickAsk.defaultChord
                == KeyChord(keyCode: 49, command: true, shift: true, option: false, control: false))
    }
}

@Suite("ShortcutBindings")
struct ShortcutBindingsTests {
    @Test("chord(for:) returns the default when no override is present")
    func chordDefaultsWhenNoOverride() {
        let bindings = ShortcutBindings()
        #expect(bindings.chord(for: .openLauncher) == ShortcutAction.openLauncher.defaultChord)
    }

    @Test("chord(for:) returns the override when present")
    func chordReturnsOverride() {
        let custom = KeyChord(keyCode: 12, command: true, shift: false, option: false, control: false)
        var bindings = ShortcutBindings()
        bindings.overrides[ShortcutAction.openLauncher.rawValue] = custom
        #expect(bindings.chord(for: .openLauncher) == custom)
    }

    @Test("action(matching:) resolves an action via its default chord")
    func actionMatchingDefault() {
        let bindings = ShortcutBindings()
        #expect(
            bindings.action(matching: 40, command: true, shift: false, option: false, control: false) == .openLauncher)
    }

    @Test("action(matching:) resolves an action via an override")
    func actionMatchingOverride() {
        var bindings = ShortcutBindings()
        let custom = KeyChord(keyCode: 12, command: true, shift: false, option: false, control: false)
        bindings.overrides[ShortcutAction.openLauncher.rawValue] = custom
        #expect(
            bindings.action(matching: 12, command: true, shift: false, option: false, control: false) == .openLauncher)
        // The old default no longer resolves to openLauncher once overridden.
        #expect(bindings.action(matching: 40, command: true, shift: false, option: false, control: false) == nil)
    }

    @Test("action(matching:) returns nil when nothing matches")
    func actionMatchingNone() {
        let bindings = ShortcutBindings()
        #expect(bindings.action(matching: 99, command: true, shift: true, option: true, control: true) == nil)
    }

    @Test("conflict(of:excluding:) detects a duplicate chord on another action")
    func conflictDetected() {
        let bindings = ShortcutBindings()
        let duplicate = ShortcutAction.toggleSettings.defaultChord
        #expect(bindings.conflict(of: duplicate, excluding: .openLauncher) == .toggleSettings)
    }

    @Test("conflict(of:excluding:) returns nil for a unique chord")
    func conflictNoneForUniqueChord() {
        let bindings = ShortcutBindings()
        let unique = KeyChord(keyCode: 99, command: true, shift: true, option: true, control: false)
        #expect(bindings.conflict(of: unique, excluding: .openLauncher) == nil)
    }

    @Test("conflict(of:excluding:) does not flag the excluded action's own chord")
    func conflictExcludesSelf() {
        let bindings = ShortcutBindings()
        let own = ShortcutAction.openLauncher.defaultChord
        #expect(bindings.conflict(of: own, excluding: .openLauncher) == nil)
    }

    @Test("decodes an empty document to no overrides")
    func decodesEmptyDocument() throws {
        let decoded = try JSONDecoder().decode(ShortcutBindings.self, from: Data("{}".utf8))
        #expect(decoded.overrides.isEmpty)
    }

    @Test("decodes a legacy payload with unrelated fields, ignoring them")
    func decodesLegacyPayload() throws {
        let legacy = Data(#"{"someFutureField":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ShortcutBindings.self, from: legacy)
        #expect(decoded.overrides.isEmpty)
    }

    @Test("round-trips overrides through a persistence store")
    func roundTripsThroughPersistence() {
        let store = InMemoryPersistenceStore()
        var bindings = ShortcutBindings()
        let custom = KeyChord(keyCode: 12, command: true, shift: false, option: false, control: false)
        bindings.overrides[ShortcutAction.closeBlock.rawValue] = custom
        store.save(bindings)
        #expect(store.load(ShortcutBindings.self)?.chord(for: .closeBlock) == custom)
    }
}

@Suite("ShortcutStore")
@MainActor
final class ShortcutStoreTests {
    @Test("rebind succeeds and persists for a free chord")
    func rebindSucceeds() {
        let persistence = InMemoryPersistenceStore()
        let store = ShortcutStore(persistence: persistence)
        let free = KeyChord(keyCode: 99, command: true, shift: true, option: true, control: false)

        let result = store.rebind(.openLauncher, to: free)

        #expect(result)
        #expect(store.chord(for: .openLauncher) == free)
        #expect(persistence.load(ShortcutBindings.self)?.chord(for: .openLauncher) == free)
    }

    @Test("rebind to a chord already used by another action fails and leaves bindings unchanged")
    func rebindConflictFails() {
        let persistence = InMemoryPersistenceStore()
        let store = ShortcutStore(persistence: persistence)
        let existing = store.chord(for: .openLauncher)

        let result = store.rebind(.toggleSettings, to: existing)

        #expect(!result)
        #expect(store.chord(for: .toggleSettings) == ShortcutAction.toggleSettings.defaultChord)
        #expect(persistence.load(ShortcutBindings.self) == nil)
    }

    @Test("resetToDefaults clears all overrides")
    func resetToDefaultsClears() {
        let persistence = InMemoryPersistenceStore()
        let store = ShortcutStore(persistence: persistence)
        let free = KeyChord(keyCode: 99, command: true, shift: true, option: true, control: false)
        _ = store.rebind(.openLauncher, to: free)

        store.resetToDefaults()

        #expect(store.chord(for: .openLauncher) == ShortcutAction.openLauncher.defaultChord)
        #expect(persistence.load(ShortcutBindings.self)?.overrides.isEmpty == true)
    }

    @Test("resetToDefault clears a single action's override")
    func resetToDefaultSingle() {
        let persistence = InMemoryPersistenceStore()
        let store = ShortcutStore(persistence: persistence)
        let free = KeyChord(keyCode: 99, command: true, shift: true, option: true, control: false)
        _ = store.rebind(.openLauncher, to: free)
        _ = store.rebind(
            .newWorkspace, to: KeyChord(keyCode: 98, command: true, shift: false, option: false, control: false))

        store.resetToDefault(.openLauncher)

        #expect(store.chord(for: .openLauncher) == ShortcutAction.openLauncher.defaultChord)
        #expect(store.chord(for: .newWorkspace).keyCode == 98)
    }

    @Test("isRecordingShortcut defaults to false and toggles freely (AIN-144)")
    func isRecordingShortcutToggles() {
        let store = ShortcutStore(persistence: InMemoryPersistenceStore())

        #expect(!store.isRecordingShortcut)

        store.isRecordingShortcut = true
        #expect(store.isRecordingShortcut)

        store.isRecordingShortcut = false
        #expect(!store.isRecordingShortcut)
    }
}
