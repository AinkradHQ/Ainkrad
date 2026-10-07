import Foundation
import Testing

@testable import Ainkrad

@Suite("Focus-Mode tab navigation")
@MainActor
struct PaneTabNavigationTests {

    /// Two columns, the second split into three rows — the shape that made
    /// geometric arrow navigation skip tabs. Tab order is the flat reading
    /// order of `blocks`, regardless of nesting.
    private func nestedLayout() -> (TileLayout, [Block]) {
        let layout = TileLayout()
        let a = layout.openApp("terminal")
        let b = layout.openApp("terminal")
        let c = layout.split(b.id, edge: .bottom)!
        let d = layout.split(c.id, edge: .bottom)!
        return (layout, [a, b, c, d])
    }

    @Test("arrows walk tab order one tab at a time, skipping none, across a nested tree")
    func walksEveryTabInOrder() {
        let (layout, _) = nestedLayout()
        let order = layout.blocks.map(\.id)
        #expect(order.count == 4)

        layout.focus(order[0])
        var visited = [order[0]]
        for _ in 1..<order.count {
            layout.focusAdjacentInOrder(offset: 1)
            visited.append(layout.focusedBlockID!)
        }
        #expect(visited == order)

        // And back again.
        var backwards = [layout.focusedBlockID!]
        for _ in 1..<order.count {
            layout.focusAdjacentInOrder(offset: -1)
            backwards.append(layout.focusedBlockID!)
        }
        #expect(backwards == order.reversed())
    }

    @Test("arrows clamp at both ends rather than wrapping")
    func clampsAtEnds() {
        let (layout, _) = nestedLayout()
        let order = layout.blocks.map(\.id)

        layout.focus(order[0])
        layout.focusAdjacentInOrder(offset: -1)
        #expect(layout.focusedBlockID == order[0])

        layout.focus(order[order.count - 1])
        layout.focusAdjacentInOrder(offset: 1)
        #expect(layout.focusedBlockID == order[order.count - 1])
    }

    @Test("a single pane has nowhere to go")
    func singlePaneIsStable() {
        let layout = TileLayout()
        let only = layout.openApp("terminal")
        layout.focusAdjacentInOrder(offset: 1)
        #expect(layout.focusedBlockID == only.id)
    }

    @Test("⌥N focuses the Nth tab in strip order")
    func focusPaneByIndex() {
        let (layout, _) = nestedLayout()
        let order = layout.blocks.map(\.id)

        layout.focusPane(at: 2)
        #expect(layout.focusedBlockID == order[2])
        layout.focusPane(at: 0)
        #expect(layout.focusedBlockID == order[0])
    }

    @Test("⌥N past the last tab does nothing — it must not clamp onto a tab the user didn't aim at")
    func outOfRangeIndexIsIgnored() {
        let layout = TileLayout()
        let a = layout.openApp("terminal")
        _ = layout.openApp("terminal")
        layout.focus(a.id)

        layout.focusPane(at: 7)
        #expect(layout.focusedBlockID == a.id)
    }

    // MARK: - The chord itself

    @Test("⌥1-⌥9 map to zero-based pane indices, matched by key code not character")
    func optionDigitChordMapsToIndex() {
        // ⌥1 emits "¡", not "1" — the mapping must not consult characters.
        let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (expected, code) in digitCodes.enumerated() {
            #expect(WorkspaceChord.paneIndex(keyCode: code, command: false, option: true, shift: false) == expected)
        }
    }

    @Test("the pane chord requires Option alone — ⌘N stays workspace switching")
    func optionDigitChordRejectsOtherModifiers() {
        #expect(WorkspaceChord.paneIndex(keyCode: 18, command: true, option: true, shift: false) == nil)
        #expect(WorkspaceChord.paneIndex(keyCode: 18, command: true, option: false, shift: false) == nil)
        #expect(WorkspaceChord.paneIndex(keyCode: 18, command: false, option: false, shift: false) == nil)
        #expect(WorkspaceChord.paneIndex(keyCode: 18, command: false, option: true, shift: true) == nil)
    }

    @Test("the setup gate blocks the pane chord, so ⌥N can't switch tabs behind the first-run wizard")
    func setupGateBlocksPaneChord() {
        #expect(WorkspaceChord.matches(keyCode: 18, characters: "¡", command: false, option: true, shift: false))
    }

    @Test("every tab the chord can reach has a label, and the tenth has none")
    func shortcutLabelsMatchTheChordsReach() {
        #expect(PaneShortcut.label(forOrdinal: 0) == "⌥1")
        #expect(PaneShortcut.label(forOrdinal: 8) == "⌥9")
        #expect(PaneShortcut.label(forOrdinal: 9) == nil)
        #expect(PaneShortcut.label(forOrdinal: -1) == nil)

        // The advertised labels and the handler's reach must agree exactly.
        let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for ordinal in 0..<PaneShortcut.maximum {
            #expect(PaneShortcut.label(forOrdinal: ordinal) != nil)
            #expect(
                WorkspaceChord.paneIndex(
                    keyCode: digitCodes[ordinal], command: false,
                    option: true, shift: false) == ordinal)
        }
    }
}
