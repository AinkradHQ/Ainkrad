import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("Undo application and refusals")
struct UndoApplyTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func makeEngine(_ mutator: InMemoryFileMutator, trash: InMemoryTrash = InMemoryTrash())
        -> (FileOperationEngine, UndoStack, InMemoryTrash)
    {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        return (FileOperationEngine(mutator: mutator, trash: trash, undoStack: stack), stack, trash)
    }

    @Test("undoing a copy deletes the copy and leaves the original")
    func undoCopy() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        #expect(mutator.fileExists(url("/b/one.txt")))

        #expect(engine.undo() == nil)
        #expect(!mutator.fileExists(url("/b/one.txt")))
        #expect(mutator.fileExists(url("/a/one.txt")))
        #expect(!stack.canUndo)
        #expect(stack.canRedo)
    }

    @Test("undoing a move puts the file back where it started")
    func undoMove() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, _, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .move, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        #expect(engine.undo() == nil)

        #expect(mutator.contents(of: "/a/one.txt") == "data")
        #expect(!mutator.fileExists(url("/b/one.txt")))
    }

    // The headline promise of the whole design: an overwrite is recoverable.
    @Test("undoing an overwrite restores the ORIGINAL content")
    func undoOverwriteRestoresOriginal() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "new")
        mutator.addFile("/b/one.txt", contents: "original")
        let trash = InMemoryTrash()
        let (engine, _, _) = makeEngine(mutator, trash: trash)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")],
                destinationDirectory: url("/b"), policy: .replace))
        #expect(mutator.contents(of: "/b/one.txt") == "new")

        #expect(engine.undo() == nil)
        // The fake trash records the restore; the real one moves bytes back.
        #expect(trash.restored == [url("/b/one.txt")])
    }

    @Test("undoing a delete restores from the Trash")
    func undoDelete() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt")
        let trash = InMemoryTrash()
        let (engine, _, _) = makeEngine(mutator, trash: trash)

        _ = await engine.submit(
            FileOperation(
                kind: .trash, sources: [url("/a/one.txt")], destinationDirectory: nil))
        #expect(engine.undo() == nil)
        #expect(trash.restored == [url("/a/one.txt")])
    }

    @Test("undoing a new folder removes it")
    func undoCreateFolder() async {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/a")
        let (engine, _, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .createFolder(name: "fresh"), sources: [], destinationDirectory: url("/a")))
        #expect(mutator.isDirectory(url("/a/fresh")))
        #expect(engine.undo() == nil)
        #expect(!mutator.isDirectory(url("/a/fresh")))
    }

    @Test("undo with an empty stack is a harmless no-op")
    func undoEmpty() {
        let (engine, _, _) = makeEngine(InMemoryFileMutator())
        #expect(engine.undo() == nil)
    }

    // MARK: - Refusals

    @Test("undo refuses when the file changed since the operation")
    func refusesExternallyModified() async {
        let mutator = ModifiableMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        // Someone else wrote to the copy after we made it.
        mutator.overriddenDates["/b/one.txt"] = Date().addingTimeInterval(600)

        let refusal = engine.undo()
        #expect(refusal == .externallyModified(url("/b/one.txt")))
        // The entry SURVIVES: the user may revert the file and retry.
        #expect(stack.canUndo)
        #expect(mutator.fileExists(url("/b/one.txt")))
    }

    @Test("undo drops an entry whose volume has gone away")
    func dropsUnavailableVolume() async {
        let mutator = ModifiableMutator()
        mutator.addFile("/a/one.txt")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        // Simulate an ejected disk properly: the whole DIRECTORY goes away,
        // not just the one file. Marking only the file unavailable modelled
        // "file deleted", which is a different thing and must NOT refuse —
        // see `UndoRefusalEdgeCaseTests`.
        mutator.unavailablePaths.insert("/b/one.txt")
        mutator.unavailablePaths.insert("/b")

        let refusal = engine.undo()
        #expect(refusal == .unavailable(url("/b/one.txt")))
        // Dropped, so the next ⌘Z reaches something applicable instead of
        // hitting the same landmine forever.
        #expect(!stack.canUndo)
    }
}

/// Mutator whose modification dates and volume availability can be forced,
/// so the two refusal paths are testable without a real ejectable disk.
private final class ModifiableMutator: InMemoryFileMutator, @unchecked Sendable {
    var overriddenDates: [String: Date] = [:]
    var unavailablePaths: Set<String> = []

    override func modificationDate(of url: URL) -> Date? {
        if unavailablePaths.contains(url.path) { return nil }
        if let forced = overriddenDates[url.path] { return forced }
        return super.modificationDate(of: url)
    }

    override func volumeIdentifier(for url: URL) -> String? {
        if unavailablePaths.contains(url.path) { return nil }
        return super.volumeIdentifier(for: url)
    }
}

@MainActor
@Suite("Redo")
struct RedoTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func makeEngine(_ mutator: InMemoryFileMutator, trash: InMemoryTrash = InMemoryTrash())
        -> (FileOperationEngine, UndoStack)
    {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        return (FileOperationEngine(mutator: mutator, trash: trash, undoStack: stack), stack)
    }

    // The original implementation re-applied the INVERSE on redo, so redoing a
    // copy tried to delete files that were already gone — a redo that
    // structurally could not redo.
    @Test("redoing a copy recreates the copy")
    func redoCopy() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, stack) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        #expect(mutator.fileExists(url("/b/one.txt")))

        engine.undo()
        #expect(!mutator.fileExists(url("/b/one.txt")))
        #expect(stack.canRedo)

        _ = await engine.redo()
        #expect(mutator.fileExists(url("/b/one.txt")), "redo must put the copy back")
    }

    @Test("redoing a move moves the file again")
    func redoMove() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "data")
        mutator.addDirectory("/b")
        let (engine, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .move, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        engine.undo()
        #expect(mutator.fileExists(url("/a/one.txt")))

        _ = await engine.redo()
        #expect(mutator.fileExists(url("/b/one.txt")))
        #expect(!mutator.fileExists(url("/a/one.txt")))
    }

    @Test("redoing a new folder recreates it")
    func redoCreateFolder() async {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/a")
        let (engine, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .createFolder(name: "fresh"), sources: [], destinationDirectory: url("/a")))
        engine.undo()
        #expect(!mutator.isDirectory(url("/a/fresh")))

        _ = await engine.redo()
        #expect(mutator.isDirectory(url("/a/fresh")))
    }

    @Test("redoing a rename applies it again")
    func redoRename() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/old.txt", contents: "x")
        let (engine, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .rename(newName: "new.txt"), sources: [url("/a/old.txt")],
                destinationDirectory: nil))
        engine.undo()
        #expect(mutator.fileExists(url("/a/old.txt")))

        _ = await engine.redo()
        #expect(mutator.fileExists(url("/a/new.txt")))
    }

    // Redone work must itself be undoable, or ⌘Z after ⌘⇧Z does nothing.
    @Test("redone work lands back on the undo stack")
    func redoIsUndoable() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt")
        mutator.addDirectory("/b")
        let (engine, stack) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))
        engine.undo()
        _ = await engine.redo()

        #expect(stack.canUndo)
        engine.undo()
        #expect(!mutator.fileExists(url("/b/one.txt")))
    }

    @Test("redo with an empty stack is a harmless no-op")
    func redoEmpty() async {
        let (engine, _) = makeEngine(InMemoryFileMutator())
        _ = await engine.redo()
    }
}

@MainActor
@Suite("Undo refusal edge cases", .serialized)
struct UndoRefusalEdgeCaseTests {
    // A trashed file is ABSENT from its original path by definition. Treating
    // absence as "volume unavailable" refused exactly the undo the Trash
    // exists to make possible.
    @Test("undoing a real delete is not refused just because the file is gone")
    func realTrashUndoNotRefused() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("undo-edge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("doomed.txt")
        try "payload".write(to: target, atomically: true, encoding: .utf8)

        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        let engine = FileOperationEngine(
            mutator: LocalFileMutator(),
            trash: SystemTrashService(), undoStack: stack)

        _ = await engine.submit(
            FileOperation(
                kind: .trash, sources: [target], destinationDirectory: nil))
        #expect(!FileManager.default.fileExists(atPath: target.path))

        let refusal = engine.undo()
        #expect(refusal == nil, "a trashed file's absence must not block its own undo")
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(try String(contentsOf: target, encoding: .utf8) == "payload")
    }
}
