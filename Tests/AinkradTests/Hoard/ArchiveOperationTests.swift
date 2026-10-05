import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Archives as engine operations.
///
/// `ArchiveService` shipped in M5 with tests and NO caller — nothing in the app
/// could reach it, and the design's inverse table ("Archive create/extract →
/// delete the product") was unimplemented. These pin the wiring: compressing
/// goes through the engine, so it is undoable like every other mutation.
@MainActor
@Suite("Archive operations")
struct ArchiveOperationTests {
    /// Records what it was asked to do and fabricates plausible products, so
    /// the engine's bookkeeping is testable without shelling out to `ditto`.
    private final class FakeArchiver: Archiving, @unchecked Sendable {
        var archiveCalls: [(sources: [URL], destination: URL)] = []
        var shouldFail = false

        func canExtract(_ url: URL) -> Bool { url.pathExtension == "zip" }

        func archive(_ sources: [URL], to destination: URL) throws -> URL {
            if shouldFail { throw ArchiveFailure(reason: "nope") }
            archiveCalls.append((sources, destination))
            return destination
        }

        func extract(_ archive: URL, into directory: URL) throws -> [URL] {
            if shouldFail { throw ArchiveFailure(reason: "nope") }
            return [
                directory.appendingPathComponent(
                    archive.deletingPathExtension().lastPathComponent)
            ]
        }
    }

    private func makeEngine(_ archiver: FakeArchiver)
        -> (FileOperationEngine, UndoStack, InMemoryFileMutator)
    {
        let mutator = InMemoryFileMutator()
        mutator.addDirectory("/a")
        mutator.addFile("/a/one.txt")
        mutator.addFile("/a/bundle.zip")
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        let engine = FileOperationEngine(
            mutator: mutator, trash: InMemoryTrash(),
            undoStack: stack, archiver: archiver)
        return (engine, stack, mutator)
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("compressing produces an archive and records a delete inverse")
    func archiveRecordsInverse() async {
        let archiver = FakeArchiver()
        let (engine, stack, _) = makeEngine(archiver)

        let result = await engine.submit(
            FileOperation(
                kind: .archive(name: "stuff.zip"), sources: [url("/a/one.txt")],
                destinationDirectory: url("/a")))

        #expect(result.succeeded == 1)
        #expect(archiver.archiveCalls.count == 1)
        // The inverse deletes the product; the inputs were never touched.
        #expect(stack.entries.last?.action == .delete([url("/a/stuff.zip")]))
    }

    @Test("undoing a compress removes the archive")
    func undoDeletesTheArchive() async {
        let archiver = FakeArchiver()
        let (engine, _, mutator) = makeEngine(archiver)
        // The fake reports success without writing, so put the product where
        // the engine believes it is.
        _ = await engine.submit(
            FileOperation(
                kind: .archive(name: "stuff.zip"), sources: [url("/a/one.txt")],
                destinationDirectory: url("/a")))
        mutator.addFile("/a/stuff.zip")

        _ = engine.undo()

        #expect(!mutator.fileExists(url("/a/stuff.zip")))
        // The source is untouched by both the operation and its inverse.
        #expect(mutator.fileExists(url("/a/one.txt")))
    }

    @Test("compressing onto an existing name is refused, not silently replaced")
    func refusesExistingName() async {
        let archiver = FakeArchiver()
        let (engine, stack, _) = makeEngine(archiver)

        let result = await engine.submit(
            FileOperation(
                kind: .archive(name: "bundle.zip"), sources: [url("/a/one.txt")],
                destinationDirectory: url("/a")))

        #expect(result.succeeded == 0)
        #expect(result.failures.count == 1)
        #expect(archiver.archiveCalls.isEmpty)
        #expect(!stack.canUndo)
    }

    @Test("a failing archiver reports the failure and records nothing")
    func failureRecordsNoInverse() async {
        let archiver = FakeArchiver()
        archiver.shouldFail = true
        let (engine, stack, _) = makeEngine(archiver)

        let result = await engine.submit(
            FileOperation(
                kind: .archive(name: "stuff.zip"), sources: [url("/a/one.txt")],
                destinationDirectory: url("/a")))

        #expect(result.succeeded == 0)
        #expect(!stack.canUndo)
    }

    @Test("extracting records the products for undo")
    func extractRecordsProducts() async {
        let archiver = FakeArchiver()
        let (engine, stack, _) = makeEngine(archiver)

        let result = await engine.submit(
            FileOperation(
                kind: .extract, sources: [url("/a/bundle.zip")],
                destinationDirectory: url("/a")))

        #expect(result.succeeded == 1)
        #expect(stack.entries.last?.action == .delete([url("/a/bundle")]))
    }

    @Test("redo re-runs the compress rather than replaying its inverse")
    func redoReRuns() async {
        let archiver = FakeArchiver()
        let (engine, _, _) = makeEngine(archiver)
        _ = await engine.submit(
            FileOperation(
                kind: .archive(name: "stuff.zip"), sources: [url("/a/one.txt")],
                destinationDirectory: url("/a")))
        _ = engine.undo()

        _ = await engine.redo()

        // Twice: once for the original, once for the redo. A redo that replayed
        // the inverse would have deleted something instead.
        #expect(archiver.archiveCalls.count == 2)
    }
}
