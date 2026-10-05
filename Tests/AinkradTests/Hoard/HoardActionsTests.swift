import AinkradHostRuntime
import AppKit
import Foundation
import Testing

@testable import Ainkrad

/// `HoardActions` is the seam every keystroke, menu item and (indirectly) the
/// assistant funnels through, and it had no tests: the milestones covered the
/// engine below it and the views above it, leaving the translation between them
/// unpinned. These cover the decisions it makes on its own — what counts as the
/// operand set, what happens when there is nowhere to paste, and which batch
/// rows are safe to apply.
@MainActor
@Suite("HoardActions", .serialized)
struct HoardActionsTests {
    @MainActor
    private struct Harness {
        let actions: HoardActions
        let store: HoardPaneStore
        let mutator: InMemoryFileMutator
        let clipboard: HoardClipboard
        var tab: HoardTab { store.activeTab }
    }

    private static let home = URL(fileURLWithPath: "/Users/test")

    /// One pane over an in-memory tree of `names`, cursor on the first row.
    private func makeHarness(_ names: [String] = ["one.txt", "two.txt", "three.txt"]) -> Harness {
        let fileSystem = InMemoryFileSystem(home: Self.home)
        fileSystem.add(directory: Self.home.path, children: names)

        let mutator = InMemoryFileMutator()
        mutator.addDirectory(Self.home.path)
        for name in names { mutator.addFile(Self.home.appendingPathComponent(name).path) }

        let engine = FileOperationEngine(
            mutator: mutator, trash: InMemoryTrash(),
            undoStack: UndoStack(persistence: InMemoryPersistenceStore()))
        let store = HoardPaneStore(
            fileSystem: fileSystem,
            persistence: InMemoryPersistenceStore())
        let coordinator = PaneCoordinator()
        let token = coordinator.register(store)
        // A private pasteboard: tests must never touch the user's clipboard.
        let clipboard = HoardClipboard(
            pasteboard: NSPasteboard(name: NSPasteboard.Name("files-actions-\(UUID().uuidString)")))

        let actions = HoardActions(
            engine: engine, coordinator: coordinator, resolver: ConflictResolver(),
            clipboard: clipboard, store: store, paneToken: token)
        return Harness(actions: actions, store: store, mutator: mutator, clipboard: clipboard)
    }

    private func url(_ name: String) -> URL { Self.home.appendingPathComponent(name) }

    // MARK: - What counts as the operand set

    @Test("an explicit selection is what gets copied")
    func selectionIsTheOperandSet() {
        let harness = makeHarness()
        harness.tab.selection = [url("one.txt"), url("two.txt")]

        harness.actions.copySelection()

        #expect(harness.clipboard.pendingOperation()?.urls.count == 2)
    }

    // The fallback that makes F5-with-no-selection do the obvious thing rather
    // than nothing at all.
    @Test("with nothing selected the cursor row is the operand")
    func cursorIsUsedWhenNothingIsSelected() {
        let harness = makeHarness()
        harness.tab.selection = []
        harness.tab.moveCursorToStart()

        harness.actions.copySelection()

        #expect(harness.clipboard.pendingOperation()?.urls == [url("one.txt")])
    }

    @Test("copying an empty pane does nothing and says nothing")
    func emptyPaneCopyIsANoOp() {
        let harness = makeHarness([])
        harness.actions.copySelection()

        #expect(!harness.clipboard.hasContents)
        #expect(harness.actions.lastToast == nil)
    }

    // MARK: - Paste

    @Test("pasting with an empty clipboard warns instead of failing silently")
    func pasteWithNothingWarns() async {
        let harness = makeHarness()
        await harness.actions.paste()

        #expect(harness.actions.lastToast?.kind == .warning)
    }

    @Test("a cut paste moves the files and then empties the clipboard")
    func cutPasteMovesAndClears() async {
        let harness = makeHarness()
        harness.mutator.addDirectory("/elsewhere")
        harness.mutator.addFile("/elsewhere/moved.txt")
        harness.clipboard.cut([URL(fileURLWithPath: "/elsewhere/moved.txt")])

        await harness.actions.paste()

        #expect(harness.mutator.fileExists(url("moved.txt")))
        #expect(!harness.mutator.fileExists(URL(fileURLWithPath: "/elsewhere/moved.txt")))
        // Leaving a consumed cut on the clipboard would let a second ⌘V try to
        // move files that are no longer there.
        #expect(!harness.clipboard.hasContents)
    }

    @Test("a copy paste leaves the clipboard loaded for a second paste")
    func copyPasteKeepsTheClipboard() async {
        let harness = makeHarness()
        harness.mutator.addDirectory("/elsewhere")
        harness.mutator.addFile("/elsewhere/kept.txt")
        harness.clipboard.copy([URL(fileURLWithPath: "/elsewhere/kept.txt")])

        await harness.actions.paste()

        #expect(harness.mutator.fileExists(url("kept.txt")))
        #expect(harness.clipboard.hasContents)
    }

    // MARK: - Cross-pane transfer

    @Test("F5 with only one pane open explains itself rather than doing nothing")
    func transferWithNoSecondPanePrompts() async {
        let harness = makeHarness()
        harness.tab.selection = [url("one.txt")]

        await harness.actions.copyToOtherPane()

        #expect(harness.actions.prompt?.id == "no-destination-false")
    }

    // MARK: - Rename

    @Test("renaming to the same name is a no-op, not a filesystem call")
    func unchangedRenameDoesNothing() async {
        let harness = makeHarness()
        let entry = harness.tab.visibleEntries[0]

        await harness.actions.commitRename(entry, to: entry.name)

        #expect(harness.actions.prompt == nil)
        #expect(harness.mutator.fileExists(url("one.txt")))
    }

    // MARK: - Batch rename

    @Test("batch rename with nothing selected says so instead of opening empty")
    func batchRenameNeedsASelection() {
        let harness = makeHarness([])
        harness.actions.beginBatchRename()

        #expect(harness.actions.batchRenameTargets == nil)
        #expect(harness.actions.lastToast?.kind == .warning)
    }

    @Test("opening batch rename snapshots the folder's names for collision checks")
    func batchRenameSnapshotsSiblings() {
        let harness = makeHarness()
        harness.tab.selection = [url("one.txt")]

        harness.actions.beginBatchRename()

        #expect(harness.actions.batchRenameTargets?.count == 1)
        #expect(harness.actions.batchRenameSiblings.contains("two.txt"))
    }

    // The invariant the preview exists to enforce: a row the sheet showed as
    // blocked must not be renamed anyway.
    @Test("applying a plan renames only the clean rows")
    func batchRenameSkipsBlockedRows() async {
        let harness = makeHarness()
        let entries = harness.tab.visibleEntries
        // "one.txt" → "renamed.txt" is clean; "two.txt" collides with a file
        // that already exists in the folder.
        let plan = batchRenamePlan(
            entries: [entries[0], entries[1]], mode: .findReplace,
            find: "one", replace: "renamed",
            existingNames: Set(entries.map(\.name)))

        await harness.actions.commitBatchRename(plan)

        #expect(harness.mutator.fileExists(url("renamed.txt")))
        #expect(!harness.mutator.fileExists(url("one.txt")))
        // Untouched: it was marked unchanged, so it must stay put.
        #expect(harness.mutator.fileExists(url("two.txt")))
        #expect(harness.actions.batchRenameTargets == nil)
    }

    @Test("applying a plan with no clean rows leaves the filesystem alone")
    func batchRenameWithNothingToDo() async {
        let harness = makeHarness()
        let plan = batchRenamePlan(
            entries: harness.tab.visibleEntries, mode: .findReplace,
            find: "no-such-substring", replace: "x", existingNames: [])

        await harness.actions.commitBatchRename(plan)

        #expect(harness.mutator.fileExists(url("one.txt")))
        #expect(harness.actions.lastToast == nil)
    }

    // "3 failed" is only useful if you can find out WHICH three and why. The
    // reasons come back from the engine; this pins that they reach the toast.
    @Test("a failure summary carries the per-item reasons")
    func failureCarriesReasons() async {
        let harness = makeHarness()
        harness.mutator.addDirectory("/elsewhere")
        harness.mutator.addFile("/elsewhere/blocked.txt")
        // An unwritable destination makes the copy fail for a stated reason.
        harness.mutator.unwritablePaths = [url("blocked.txt").path]
        harness.clipboard.copy([URL(fileURLWithPath: "/elsewhere/blocked.txt")])

        await harness.actions.paste()

        #expect(harness.actions.lastToast?.kind == .failure)
        #expect(harness.actions.lastToast?.failures.count == 1)
        #expect(harness.actions.lastToast?.failures.first?.reason.isEmpty == false)
    }

}
