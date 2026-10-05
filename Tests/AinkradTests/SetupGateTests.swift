import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup gate")
@MainActor
struct SetupGateTests {
    // Plain text must reach the overlay. This is the bug that made four of the
    // wizard's eight steps unusable: every field was inert because the gate
    // consumed the keystroke before AppKit delivered it.
    @Test func plainCharactersReachTheOverlayWhileGated() {
        #expect(
            !SetupGate.swallows(
                isSetupPresented: true, isConfirmingQuit: false,
                isRegisteredShortcut: false, isWorkspaceChord: false,
                command: false, characters: "a", keyCode: 0))
    }

    @Test func editingChordsReachTheOverlayWhileGated() {
        for character in ["a", "c", "v", "x", "z"] {
            #expect(
                !SetupGate.swallows(
                    isSetupPresented: true, isConfirmingQuit: false,
                    isRegisteredShortcut: false, isWorkspaceChord: false,
                    command: true, characters: character, keyCode: 0),
                "⌘\(character.uppercased()) must reach a focused text field")
        }
    }

    @Test func registeredWorkspaceShortcutsAreSwallowedWhileGated() {
        #expect(
            SetupGate.swallows(
                isSetupPresented: true, isConfirmingQuit: false,
                isRegisteredShortcut: true, isWorkspaceChord: false,
                command: true, characters: "k", keyCode: 40))
    }

    @Test func hardcodedWorkspaceChordsAreSwallowedWhileGated() {
        #expect(
            SetupGate.swallows(
                isSetupPresented: true, isConfirmingQuit: false,
                isRegisteredShortcut: false, isWorkspaceChord: true,
                command: true, characters: "1", keyCode: 18))
    }

    // The trap that has now appeared four times at four depths.
    @Test func commandQAlwaysEscapes() {
        #expect(
            !SetupGate.swallows(
                isSetupPresented: true, isConfirmingQuit: false,
                isRegisteredShortcut: true, isWorkspaceChord: true,
                command: true, characters: "q", keyCode: 12))
    }

    // Dvorak puts "q" on keyCode 39, AZERTY on 0. Matching the physical key
    // strands those users with no keyboard escape.
    @Test func commandQEscapesOnNonQwertyLayouts() {
        for keyCode: UInt16 in [39, 0] {
            #expect(keyCode != 12)
            #expect(
                !SetupGate.swallows(
                    isSetupPresented: true, isConfirmingQuit: false,
                    isRegisteredShortcut: false, isWorkspaceChord: false,
                    command: true, characters: "q", keyCode: keyCode))
        }
    }

    @Test func quitConfirmationKeysPassOnlyWhileConfirming() {
        for keyCode: UInt16 in [36, 76, 53] {
            #expect(
                !SetupGate.swallows(
                    isSetupPresented: true, isConfirmingQuit: true,
                    isRegisteredShortcut: false, isWorkspaceChord: false,
                    command: false, characters: nil, keyCode: keyCode))
        }
    }

    @Test func nothingIsSwallowedWhenTheGateIsDown() {
        #expect(
            !SetupGate.swallows(
                isSetupPresented: false, isConfirmingQuit: false,
                isRegisteredShortcut: true, isWorkspaceChord: true,
                command: true, characters: "k", keyCode: 40))
    }
}

/// The set of hardcoded chords the gate blocks. `SetupGate` can only uphold
/// "anything `handle` would act on is swallowed" if `WorkspaceChord.matches`
/// enumerates every one of them — a chord `handle` performs but `matches` omits
/// falls straight past the gate and mutates the workspace behind the wizard.
@Suite("Workspace chords")
@MainActor
struct WorkspaceChordTests {
    private static let one: UInt16 = 18
    private static let d: UInt16 = 2
    private static let m: UInt16 = 46
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126

    /// Every chord `KeyboardShortcutMonitor.handle` acts on without consulting a
    /// `ShortcutAction` binding. If a branch is added to `handle`, it belongs here.
    private static let all:
        [(
            name: String, keyCode: UInt16, characters: String?,
            option: Bool, shift: Bool
        )] = [
            ("⌘1 switch workspace", one, "1", false, false),
            ("⌘← focus pane", leftArrow, nil, false, false),
            ("⌘→ focus pane", rightArrow, nil, false, false),
            ("⌘↓ focus pane", downArrow, nil, false, false),
            ("⌘↑ focus pane", upArrow, nil, false, false),
            ("⌘⇧← resize pane", leftArrow, nil, false, true),
            ("⌘⌥← cycle workspace", leftArrow, nil, true, false),
            ("⌘⌥→ cycle workspace", rightArrow, nil, true, false),
            ("⌘D split trailing", d, "d", false, false),
            ("⌘⇧D split bottom", d, "d", false, true),
            ("⌘M toggle focus mode", m, "m", false, false),
        ]

    // ⌘D splits the focused pane and ⌘M toggles view mode AND calls
    // `workspaceManager.persist()` — while gated that writes into the
    // provisional home, a temp directory discarded at the vault swap. Both
    // leaked through the first version of the gate.
    @Test func everyHardcodedChordIsSwallowedWhileGated() {
        for chord in Self.all {
            #expect(
                WorkspaceChord.matches(
                    keyCode: chord.keyCode, characters: chord.characters,
                    command: true, option: chord.option, shift: chord.shift),
                "\(chord.name) must be a recognised workspace chord")
            #expect(
                SetupGate.swallows(
                    isSetupPresented: true, isConfirmingQuit: false,
                    isRegisteredShortcut: false,
                    isWorkspaceChord: WorkspaceChord.matches(
                        keyCode: chord.keyCode, characters: chord.characters,
                        command: true, option: chord.option, shift: chord.shift),
                    command: true, characters: chord.characters,
                    keyCode: chord.keyCode),
                "\(chord.name) must not reach the workspace while setup is presented")
        }
    }

    @Test func everyHardcodedChordWorksAgainOnceTheGateIsDown() {
        for chord in Self.all {
            #expect(
                !SetupGate.swallows(
                    isSetupPresented: false, isConfirmingQuit: false,
                    isRegisteredShortcut: false,
                    isWorkspaceChord: true,
                    command: true, characters: chord.characters,
                    keyCode: chord.keyCode),
                "\(chord.name) must work again once setup is dismissed")
        }
    }

    /// Without ⌘ these are ordinary typing — "d", "m" and "1" must reach a
    /// focused text field in the wizard.
    @Test func theSameKeysWithoutCommandAreJustTyping() {
        for characters in ["d", "m", "1"] {
            #expect(
                !WorkspaceChord.matches(
                    keyCode: 0, characters: characters,
                    command: false, option: false, shift: false),
                "bare \"\(characters)\" is typing, not a chord")
        }
    }

    @Test func splitAndFocusModeResolveTheSameWayTheBranchesPerformThem() {
        #expect(WorkspaceChord.splitEdge(characters: "d", command: true, shift: false) == .trailing)
        #expect(WorkspaceChord.splitEdge(characters: "d", command: true, shift: true) == .bottom)
        #expect(WorkspaceChord.splitEdge(characters: "d", command: false, shift: false) == nil)
        // ⌘⇧M is not a binding — the branch is `where !isShifted`.
        #expect(WorkspaceChord.togglesFocusMode(characters: "m", command: true, shift: false))
        #expect(!WorkspaceChord.togglesFocusMode(characters: "m", command: true, shift: true))
        #expect(!WorkspaceChord.togglesFocusMode(characters: "m", command: false, shift: false))
    }

    /// Editing chords share no key with the blocking set, so they still reach
    /// the overlay's text fields.
    @Test func editingChordsAreNotWorkspaceChords() {
        for characters in ["a", "c", "v", "x", "z", "q"] {
            #expect(
                !WorkspaceChord.matches(
                    keyCode: 0, characters: characters,
                    command: true, option: false, shift: false),
                "⌘\(characters.uppercased()) must reach a focused text field")
        }
    }
}
