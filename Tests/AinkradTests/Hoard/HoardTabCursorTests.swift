import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("HoardTab cursor and selection")
struct HoardTabCursorTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeTab() -> HoardTab {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Documents/", "a.txt", "b.txt"])
        fs.add(directory: "/Users/test/Documents", children: ["report.pdf"])
        return HoardTab(directory: home, fileSystem: fs)
    }

    @Test("cursor starts at the first row")
    func startsAtZero() {
        #expect(makeTab().cursorIndex == 0)
    }

    @Test("moving the cursor clamps at both ends")
    func clamps() {
        let tab = makeTab()
        tab.moveCursor(by: -1)
        #expect(tab.cursorIndex == 0)
        tab.moveCursor(by: 99)
        #expect(tab.cursorIndex == 2)
    }

    @Test("cursorEntry tracks the visible ordering")
    func cursorEntry() {
        let tab = makeTab()
        #expect(tab.cursorEntry?.name == "Documents")
        tab.moveCursor(by: 1)
        #expect(tab.cursorEntry?.name == "a.txt")
    }

    @Test("start and end jump to the extremes")
    func startEnd() {
        let tab = makeTab()
        tab.moveCursorToEnd()
        #expect(tab.cursorIndex == 2)
        tab.moveCursorToStart()
        #expect(tab.cursorIndex == 0)
    }

    @Test("selecting the cursor replaces the selection by default")
    func selectReplaces() {
        let tab = makeTab()
        tab.selectCursor(extending: false)
        tab.moveCursor(by: 1)
        tab.selectCursor(extending: false)
        #expect(tab.selection.count == 1)
    }

    @Test("extending adds to the selection")
    func selectExtends() {
        let tab = makeTab()
        tab.selectCursor(extending: false)
        tab.moveCursor(by: 1)
        tab.selectCursor(extending: true)
        #expect(tab.selection.count == 2)
    }

    @Test("select all and invert")
    func selectAllAndInvert() {
        let tab = makeTab()
        tab.selectAll()
        #expect(tab.selection.count == 3)
        tab.invertSelection()
        #expect(tab.selection.isEmpty)
    }

    @Test("invert on a partial selection selects the complement")
    func invertPartial() {
        let tab = makeTab()
        tab.selectCursor(extending: false)
        tab.invertSelection()
        #expect(tab.selection.count == 2)
        #expect(!tab.selection.contains(tab.visibleEntries[0].url))
    }

    @Test("activating a directory descends and resets the cursor")
    func activateDescends() {
        let tab = makeTab()
        tab.activateCursor()
        #expect(tab.currentDirectory == home.appendingPathComponent("Documents"))
        #expect(tab.cursorIndex == 0)
    }

    @Test("space toggles the cursor row in and out of the selection")
    func toggleSelection() {
        let tab = makeTab()
        tab.toggleCursorSelection()
        #expect(tab.selection.count == 1)
        tab.toggleCursorSelection()
        #expect(tab.selection.isEmpty)
    }

    @Test("clicking a row moves the cursor there")
    func placeCursor() {
        let tab = makeTab()
        let target = tab.visibleEntries[2]
        tab.placeCursor(at: target)
        #expect(tab.cursorIndex == 2)
        #expect(tab.selection == [target.url])
    }

    // `visibleEntries` is a CACHE, so every input that feeds it must
    // invalidate it. A stale cache here would show the wrong files.
    @Test("changing the sort key refreshes the cached listing")
    func sortKeyInvalidatesCache() {
        let tab = makeTab()
        #expect(tab.visibleEntries.map(\.name) == ["Documents", "a.txt", "b.txt"])
        tab.sortAscending = false
        #expect(tab.visibleEntries.map(\.name) == ["Documents", "b.txt", "a.txt"])
        tab.sortKey = .size
        #expect(tab.visibleEntries.first?.name == "Documents")
    }

    @Test("toggling hidden files refreshes the cached listing")
    func showHiddenInvalidatesCache() {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["a.txt", ".secret"])
        let tab = HoardTab(directory: home, fileSystem: fs)
        #expect(tab.visibleEntries.count == 1)
        tab.showHidden = true
        #expect(tab.visibleEntries.count == 2)
        tab.showHidden = false
        #expect(tab.visibleEntries.count == 1)
    }

    @Test("reloading refreshes the cached listing")
    func reloadInvalidatesCache() {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["a.txt"])
        let tab = HoardTab(directory: home, fileSystem: fs)
        #expect(tab.visibleEntries.count == 1)
        fs.add(directory: "/Users/test", children: ["a.txt", "b.txt"])
        tab.reload()
        #expect(tab.visibleEntries.count == 2)
    }

    @Test("the cursor stays in range when the listing shrinks")
    func cursorSurvivesShrink() {
        let tab = makeTab()
        tab.moveCursorToEnd()
        tab.showHidden = true
        tab.navigate(to: home.appendingPathComponent("Documents"))
        #expect(tab.cursorIndex == 0)
        #expect(tab.cursorEntry?.name == "report.pdf")
    }
}
