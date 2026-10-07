import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("FileOperationEngine")
struct FileOperationEngineTests {
    private func makeEngine(_ mutator: InMemoryFileMutator, trash: InMemoryTrash = InMemoryTrash())
        -> (FileOperationEngine, UndoStack, InMemoryTrash)
    {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        return (FileOperationEngine(mutator: mutator, trash: trash, undoStack: stack), stack, trash)
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    // MARK: - Copy

    @Test("copy creates the file and records a delete inverse")
    func copyCreatesAndRecords() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "hello")
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        #expect(result.succeeded == 1)
        #expect(mutator.contents(of: "/b/one.txt") == "hello")
        #expect(mutator.contents(of: "/a/one.txt") == "hello")
        #expect(stack.canUndo)
        #expect(stack.entries.last?.action == .delete([url("/b/one.txt")]))
    }

    // MARK: - Move

    @Test("a same-volume move moves and records a move-back inverse")
    func sameVolumeMove() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt")
        mutator.addDirectory("/b")
        let (engine, stack, trash) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .move, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        #expect(!mutator.fileExists(url("/a/one.txt")))
        #expect(mutator.fileExists(url("/b/one.txt")))
        #expect(trash.trashedCount == 0)
        #expect(
            stack.entries.last?.action
                == .moveBack([MovedItem(from: url("/b/one.txt"), to: url("/a/one.txt"))]))
    }

    @Test("a cross-volume move copies then TRASHES the source, never unlinks it")
    func crossVolumeMove() async {
        let mutator = InMemoryFileMutator()
        mutator.mountVolume("external", at: "/ext")
        mutator.addFile("/ext/one.txt", contents: "payload")
        mutator.addDirectory("/b")
        let (engine, stack, trash) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .move, sources: [url("/ext/one.txt")], destinationDirectory: url("/b")))

        #expect(mutator.contents(of: "/b/one.txt") == "payload")
        // The source must be recoverable — that is what makes the move
        // invertible across volumes.
        #expect(trash.trashedCount == 1)
        if case .composite(let actions) = stack.entries.last?.action {
            #expect(actions.count == 2)
        } else {
            Issue.record("expected a composite inverse for a cross-volume move")
        }
    }

    // MARK: - Conflicts

    @Test("overwrite trashes the displaced file BEFORE writing, so undo can restore it")
    func overwriteTrashesFirst() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "new")
        mutator.addFile("/b/one.txt", contents: "original")
        let (engine, stack, trash) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")],
                destinationDirectory: url("/b"), policy: .replace))

        #expect(mutator.contents(of: "/b/one.txt") == "new")
        #expect(trash.trashedCount == 1)
        if case .composite(let actions) = stack.entries.last?.action {
            #expect(actions.first == .delete([url("/b/one.txt")]))
        } else {
            Issue.record("expected a composite inverse for an overwrite")
        }
    }

    @Test("keep-both suffixes instead of replacing")
    func keepBoth() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "new")
        mutator.addFile("/b/one.txt", contents: "original")
        let (engine, _, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")],
                destinationDirectory: url("/b"), policy: .keepBoth))

        #expect(mutator.contents(of: "/b/one.txt") == "original")
        #expect(mutator.contents(of: "/b/one 2.txt") == "new")
    }

    @Test("skip leaves the destination untouched")
    func skip() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "new")
        mutator.addFile("/b/one.txt", contents: "original")
        let (engine, stack, _) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")],
                destinationDirectory: url("/b"), policy: .skip))

        #expect(result.skipped == 1)
        #expect(mutator.contents(of: "/b/one.txt") == "original")
        // Nothing happened, so nothing may be pushed — an empty undo entry
        // would make ⌘Z appear to do nothing.
        #expect(!stack.canUndo)
    }

    @Test("with no resolver and no policy, a conflict skips rather than destroys")
    func failsClosedOnConflict() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt", contents: "new")
        mutator.addFile("/b/one.txt", contents: "original")
        let (engine, _, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .copy, sources: [url("/a/one.txt")], destinationDirectory: url("/b")))

        #expect(mutator.contents(of: "/b/one.txt") == "original")
    }

    @Test("apply-to-all answers every later conflict without asking again")
    func applyToAll() async {
        let mutator = InMemoryFileMutator()
        for name in ["one", "two", "three"] {
            mutator.addFile("/a/\(name).txt", contents: "new")
            mutator.addFile("/b/\(name).txt", contents: "original")
        }
        let (engine, _, _) = makeEngine(mutator)

        let asked = Counter()
        _ = await engine.submit(
            FileOperation(
                kind: .copy,
                sources: ["one", "two", "three"].map { url("/a/\($0).txt") },
                destinationDirectory: url("/b")),
            conflictResolver: { _ in
                asked.increment()
                return ConflictAnswer(policy: .replace, applyToAll: true)
            })

        #expect(asked.value == 1)
        #expect(mutator.contents(of: "/b/two.txt") == "new")
    }

    // MARK: - Robustness

    @Test("one failing item does not abort the rest of the batch")
    func partialFailure() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt")
        mutator.addFile("/a/two.txt")
        mutator.addFile("/a/three.txt")
        mutator.addDirectory("/b")
        mutator.unwritablePaths = ["/b/two.txt"]
        let (engine, _, _) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .copy,
                sources: ["one", "two", "three"].map { url("/a/\($0).txt") },
                destinationDirectory: url("/b")))

        #expect(result.succeeded == 2)
        #expect(result.failures.count == 1)
        #expect(mutator.fileExists(url("/b/three.txt")))
    }

    @Test("an empty source list is a no-op that records nothing")
    func emptySources() async {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .copy, sources: [], destinationDirectory: url("/b")))

        #expect(result.succeeded == 0)
        #expect(!stack.canUndo)
    }

    // MARK: - Rename, folder, trash

    @Test("rename moves in place and records a rename-back")
    func rename() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/old.txt", contents: "data")
        let (engine, stack, _) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .rename(newName: "new.txt"), sources: [url("/a/old.txt")],
                destinationDirectory: nil))

        #expect(result.succeeded == 1)
        #expect(mutator.contents(of: "/a/new.txt") == "data")
        #expect(stack.entries.last?.label == "Rename")
    }

    @Test("rename onto an existing name fails instead of clobbering")
    func renameConflict() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/old.txt", contents: "data")
        mutator.addFile("/a/taken.txt", contents: "other")
        let (engine, stack, _) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .rename(newName: "taken.txt"), sources: [url("/a/old.txt")],
                destinationDirectory: nil))

        #expect(result.failures.count == 1)
        #expect(mutator.contents(of: "/a/taken.txt") == "other")
        #expect(!stack.canUndo)
    }

    @Test("new folder is created and inverts to deleting it")
    func createFolder() async {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/a")
        let (engine, stack, _) = makeEngine(mutator)

        _ = await engine.submit(
            FileOperation(
                kind: .createFolder(name: "fresh"), sources: [], destinationDirectory: url("/a")))

        #expect(mutator.isDirectory(url("/a/fresh")))
        #expect(stack.entries.last?.action == .delete([url("/a/fresh")]))
    }

    @Test("delete routes to the Trash, never an unlink")
    func trashItems() async {
        let mutator = InMemoryFileMutator()
        mutator.addFile("/a/one.txt")
        mutator.addFile("/a/two.txt")
        let (engine, stack, trash) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .trash, sources: [url("/a/one.txt"), url("/a/two.txt")],
                destinationDirectory: nil))

        #expect(result.succeeded == 2)
        #expect(trash.trashedCount == 2)
        if case .restoreFromTrash(let items) = stack.entries.last?.action {
            #expect(items.count == 2)
        } else {
            Issue.record("expected a restore-from-trash inverse for a delete")
        }
    }

    // MARK: - Cancellation

    @Test("a cancelled job stops, and its inverse covers only completed items")
    func cancellation() async {
        let mutator = InMemoryFileMutator()
        for index in 0..<5 { mutator.addFile("/a/\(index).txt") }
        mutator.addDirectory("/b")
        let (engine, stack, _) = makeEngine(mutator)

        // Cancel as soon as the job appears, so it stops partway through.
        let operation = FileOperation(
            kind: .copy, sources: (0..<5).map { url("/a/\($0).txt") },
            destinationDirectory: url("/b"))
        async let submitted = engine.submit(operation)
        engine.activeJobs.first?.cancel()
        let result = await submitted

        if case .delete(let urls) = stack.entries.last?.action {
            // Whatever it managed, the inverse must cover exactly that — no
            // more (undo would delete files it didn't create) and no less
            // (undo would leave copies behind).
            #expect(urls.count == result.succeeded)
        } else if result.succeeded > 0 {
            Issue.record("a partially-completed copy must still record an inverse")
        }
    }
}

/// Reference counter for assertions inside `@Sendable` closures.
private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}
