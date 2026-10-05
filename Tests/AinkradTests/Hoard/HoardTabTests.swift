import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("HoardTab")
struct HoardTabTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeFS() -> InMemoryFileSystem {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Documents/", "notes.txt", ".hidden"])
        fs.add(directory: "/Users/test/Documents", children: ["report.pdf"])
        return fs
    }

    @Test("loads its directory on creation")
    func loadsOnInit() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        #expect(tab.currentDirectory == home)
        #expect(tab.entries.count == 3)
        #expect(tab.loadError == nil)
    }

    @Test("hides dotfiles by default")
    func hidesHidden() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        #expect(tab.visibleEntries.map(\.name) == ["Documents", "notes.txt"])
        tab.showHidden = true
        #expect(tab.visibleEntries.count == 3)
    }

    @Test("descending into a directory navigates and reloads")
    func descend() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        let documents = tab.visibleEntries.first { $0.name == "Documents" }!
        tab.descend(into: documents)
        #expect(tab.currentDirectory == home.appendingPathComponent("Documents"))
        #expect(tab.visibleEntries.map(\.name) == ["report.pdf"])
    }

    @Test("descending into a file does nothing")
    func descendIntoFileIsNoop() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        let file = tab.visibleEntries.first { $0.name == "notes.txt" }!
        tab.descend(into: file)
        #expect(tab.currentDirectory == home)
    }

    @Test("ascending goes to the parent")
    func ascend() {
        let tab = HoardTab(directory: home.appendingPathComponent("Documents"), fileSystem: makeFS())
        tab.ascend()
        #expect(tab.currentDirectory == home)
    }

    @Test("back and forward retrace navigation")
    func backForward() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        tab.descend(into: tab.visibleEntries.first { $0.name == "Documents" }!)
        tab.goBack()
        #expect(tab.currentDirectory == home)
        tab.goForward()
        #expect(tab.currentDirectory == home.appendingPathComponent("Documents"))
    }

    @Test("navigation clears the selection")
    func navigationClearsSelection() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        tab.selection = [home.appendingPathComponent("notes.txt")]
        tab.descend(into: tab.visibleEntries.first { $0.name == "Documents" }!)
        #expect(tab.selection.isEmpty)
    }

    @Test("an unreadable directory surfaces an error and empties the list")
    func loadError() {
        let tab = HoardTab(directory: URL(fileURLWithPath: "/nope"), fileSystem: makeFS())
        #expect(tab.loadError != nil)
        #expect(tab.entries.isEmpty)
    }

    @Test("a failed navigation still moves, so the error is visible in place")
    func failedNavigationIsVisible() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        tab.navigate(to: URL(fileURLWithPath: "/nope"))
        #expect(tab.currentDirectory == URL(fileURLWithPath: "/nope"))
        #expect(tab.loadError != nil)
    }

    @Test("sort key and direction reorder the visible entries")
    func sorting() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        tab.sortAscending = false
        #expect(tab.visibleEntries.map(\.name) == ["Documents", "notes.txt"])
        tab.showHidden = true
        #expect(tab.visibleEntries.map(\.name) == ["Documents", "notes.txt", ".hidden"])
    }

    @Test("title is the directory's last component")
    func title() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        #expect(tab.title == "test")
        tab.descend(into: tab.visibleEntries.first { $0.name == "Documents" }!)
        #expect(tab.title == "Documents")
    }

    // ⌘. and ⌘⇧. are different questions: "show me dotfiles" is about the
    // filesystem, "show me what git is ignoring" is about the project. They
    // were one toggle until 2026-08-01, which meant you could not see
    // node_modules without also seeing every dotfile.
    @Test("dotfiles and git-ignored files toggle independently")
    func hiddenAndIgnoredAreSeparate() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        tab.ignoredURLs = [home.appendingPathComponent("notes.txt")]
        #expect(tab.visibleEntries.map(\.name) == ["Documents"])

        // Ignored only: notes.txt returns, the dotfile stays hidden.
        tab.showIgnored = true
        #expect(tab.visibleEntries.map(\.name) == ["Documents", "notes.txt"])

        // Hidden only: the dotfile returns, the ignored file goes away again.
        tab.showIgnored = false
        tab.showHidden = true
        // Directories sort first, so the dotfile lands after "Documents".
        #expect(tab.visibleEntries.map(\.name) == ["Documents", ".hidden"])

        tab.showIgnored = true
        #expect(tab.visibleEntries.count == 3)
    }

    // Reported 2026-08-02: launch on Desktop (correct), sidebar to Downloads,
    // sidebar back to Desktop — EMPTY pane. Sidebar Home, then sidebar Desktop
    // again — correct. Both failing and working routes are sidebar clicks with
    // the identical URL, so if the model were at fault this would reproduce it.
    // It does not, which is what places the defect above `HoardTab`.
    @Test("revisiting a directory by URL lists it again")
    func revisitingRelistsTheDirectory() {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Desktop/", "Downloads/"])
        fs.add(directory: "/Users/test/Desktop", children: ["poster.png", "notes.md"])
        fs.add(directory: "/Users/test/Downloads", children: ["installer.dmg"])

        let desktop = home.appendingPathComponent("Desktop")
        let tab = HoardTab(directory: desktop, fileSystem: fs)
        #expect(tab.visibleEntries.count == 2)

        tab.navigate(to: home.appendingPathComponent("Downloads"))
        #expect(tab.visibleEntries.map(\.name) == ["installer.dmg"])

        // The step that fails in the app.
        tab.navigate(to: desktop)
        #expect(tab.currentDirectory == desktop)
        #expect(tab.loadError == nil)
        #expect(tab.visibleEntries.count == 2)

        // And the route that recovers it.
        tab.navigate(to: home)
        tab.navigate(to: desktop)
        #expect(tab.visibleEntries.count == 2)
    }

    // Right-clicking one of three selected files must act on all three;
    // right-clicking a fourth acts on that one alone. Backwards, this is a
    // menu that appears over one file and deletes others.
    @Test("a context menu on a selected row keeps the whole selection")
    func contextMenuKeepsSelection() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        let entries = tab.visibleEntries
        tab.selection = Set(entries.map(\.url))

        tab.targetContextMenu(at: entries[0])

        #expect(tab.selection.count == entries.count)
    }

    @Test("a context menu on an unselected row retargets onto it alone")
    func contextMenuRetargets() {
        let tab = HoardTab(directory: home, fileSystem: makeFS())
        let entries = tab.visibleEntries
        tab.selection = [entries[0].url]

        tab.targetContextMenu(at: entries[1])

        // Solely selected AND cursored — the menu's actions read the
        // selection, so it must name exactly the row that was clicked.
        #expect(tab.selection == [entries[1].url])
        #expect(tab.cursorEntry == entries[1])
    }

}
