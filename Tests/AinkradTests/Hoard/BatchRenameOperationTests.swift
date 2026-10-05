import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// The engine side of batch rename: many renames recorded as ONE undo entry.
///
/// The sheet originally submitted a rename per row, which meant undoing a
/// 200-file rename was 200 ⌘Z — reversible on paper, not in practice. These
/// pin the single-entry behaviour and the round trip through undo and redo.
@MainActor
@Suite("Batch rename operation")
struct BatchRenameOperationTests {
    private func makeEngine(_ mutator: InMemoryFileMutator) -> (FileOperationEngine, UndoStack) {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        return (
            FileOperationEngine(mutator: mutator, trash: InMemoryTrash(), undoStack: stack),
            stack
        )
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func makeTree(_ names: [String]) -> InMemoryFileMutator {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/a")
        for name in names { mutator.addFile("/a/\(name)") }
        return mutator
    }

    @Test("renames every file and records exactly one undo entry")
    func renamesAsOneEntry() async {
        let mutator = makeTree(["one.txt", "two.txt", "three.txt"])
        let (engine, stack) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: ["1.txt", "2.txt", "3.txt"]),
                sources: [url("/a/one.txt"), url("/a/two.txt"), url("/a/three.txt")],
                destinationDirectory: nil))

        #expect(result.succeeded == 3)
        #expect(mutator.fileExists(url("/a/1.txt")))
        #expect(!mutator.fileExists(url("/a/one.txt")))
        // The whole point: three renames, ONE entry.
        #expect(stack.entries.count == 1)
    }

    @Test("one undo puts every name back")
    func oneUndoRestoresTheWholeBatch() async {
        let mutator = makeTree(["one.txt", "two.txt"])
        let (engine, _) = makeEngine(mutator)
        _ = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: ["1.txt", "2.txt"]),
                sources: [url("/a/one.txt"), url("/a/two.txt")], destinationDirectory: nil))

        #expect(engine.undo() == nil)

        #expect(mutator.fileExists(url("/a/one.txt")))
        #expect(mutator.fileExists(url("/a/two.txt")))
        #expect(!mutator.fileExists(url("/a/1.txt")))
    }

    @Test("redo re-applies the whole batch")
    func redoReappliesTheBatch() async {
        let mutator = makeTree(["one.txt", "two.txt"])
        let (engine, _) = makeEngine(mutator)
        _ = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: ["1.txt", "2.txt"]),
                sources: [url("/a/one.txt"), url("/a/two.txt")], destinationDirectory: nil))
        _ = engine.undo()

        _ = await engine.redo()

        #expect(mutator.fileExists(url("/a/1.txt")))
        #expect(mutator.fileExists(url("/a/2.txt")))
    }

    // Positional arrays out of step would rename files under each other's
    // names — the one failure mode that silently produces plausible garbage.
    @Test("a name-count mismatch refuses the whole operation")
    func mismatchedCountsRefuse() async {
        let mutator = makeTree(["one.txt", "two.txt"])
        let (engine, stack) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: ["only-one.txt"]),
                sources: [url("/a/one.txt"), url("/a/two.txt")], destinationDirectory: nil))

        #expect(result.succeeded == 0)
        #expect(result.failures.count == 1)
        #expect(mutator.fileExists(url("/a/one.txt")))
        #expect(!stack.canUndo)
    }

    @Test("a row whose name is taken fails without stopping the rest")
    func occupiedNameFailsOnlyThatRow() async {
        let mutator = makeTree(["one.txt", "two.txt", "taken.txt"])
        let (engine, stack) = makeEngine(mutator)

        let result = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: ["taken.txt", "2.txt"]),
                sources: [url("/a/one.txt"), url("/a/two.txt")], destinationDirectory: nil))

        #expect(result.succeeded == 1)
        #expect(result.failures.count == 1)
        #expect(mutator.fileExists(url("/a/one.txt")))  // untouched
        #expect(mutator.fileExists(url("/a/2.txt")))
        #expect(stack.entries.count == 1)
    }

    // A partial batch must still be wholly undoable — the inverse covers
    // exactly what landed, no more.
    @Test("undoing a partial batch restores only what actually happened")
    func partialBatchUndoesCleanly() async {
        let mutator = makeTree(["one.txt", "two.txt", "taken.txt"])
        let (engine, _) = makeEngine(mutator)
        _ = await engine.submit(
            FileOperation(
                kind: .batchRename(newNames: ["taken.txt", "2.txt"]),
                sources: [url("/a/one.txt"), url("/a/two.txt")], destinationDirectory: nil))

        _ = engine.undo()

        #expect(mutator.fileExists(url("/a/two.txt")))
        #expect(!mutator.fileExists(url("/a/2.txt")))
        // The pre-existing file the failed row collided with is untouched.
        #expect(mutator.fileExists(url("/a/taken.txt")))
    }
}
