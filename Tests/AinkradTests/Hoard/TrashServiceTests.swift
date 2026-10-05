import Foundation
import Testing

@testable import Ainkrad

@Suite("TrashService")
struct TrashServiceTests {
    @Test("trashing returns the item's new location and restore puts it back")
    func trashAndRestore() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("doomed.txt")
        try "bytes".write(to: file, atomically: true, encoding: .utf8)

        let service = SystemTrashService()
        let trashed = try service.trash(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: trashed.path))

        try service.restore(from: trashed, to: file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: file, encoding: .utf8) == "bytes")

        try? FileManager.default.removeItem(at: trashed)
    }

    @Test("trashing something that does not exist throws")
    func trashMissing() {
        let service = SystemTrashService()
        #expect(throws: (any Error).self) {
            try service.trash(URL(fileURLWithPath: "/nope-\(UUID().uuidString)"))
        }
    }

    @Test("the in-memory fake mirrors trash-then-restore for unit tests")
    func inMemoryFake() throws {
        let trash = InMemoryTrash()
        let original = URL(fileURLWithPath: "/vol/a.txt")

        let trashed = try trash.trash(original)
        #expect(trash.contains(trashed))
        try trash.restore(from: trashed, to: original)
        #expect(!trash.contains(trashed))
        #expect(trash.restored == [original])
    }

    @Test("the fake refuses to restore something it never trashed")
    func fakeRefusesUnknownRestore() {
        let trash = InMemoryTrash()
        #expect(throws: (any Error).self) {
            try trash.restore(
                from: URL(fileURLWithPath: "/trash/ghost"),
                to: URL(fileURLWithPath: "/vol/ghost"))
        }
    }
}
