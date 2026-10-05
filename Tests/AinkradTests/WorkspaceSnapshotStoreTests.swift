import Foundation
import Testing

@testable import Ainkrad

@Suite("WorkspaceSnapshotStore")
struct WorkspaceSnapshotStoreTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cp-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func snapshotsAndRestoresExistingFileBytes() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceSnapshotStore(root: root)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let id = UUID()
        let snap = store.snapshotFile(file.path, into: id)
        #expect(snap.existedBefore)
        #expect(snap.blobName != nil)

        try "mutated".write(to: file, atomically: true, encoding: .utf8)
        store.restore(snap, from: id)
        #expect((try? String(contentsOf: file, encoding: .utf8)) == "original")
    }

    @Test func restoreOfNonExistentFileSnapshotDeletesRecreatedFile() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceSnapshotStore(root: root)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("n-\(UUID().uuidString).txt")

        let id = UUID()
        let snap = store.snapshotFile(file.path, into: id)  // file does not exist yet
        #expect(!snap.existedBefore)
        #expect(snap.blobName == nil)

        try "created-by-agent".write(to: file, atomically: true, encoding: .utf8)
        store.restore(snap, from: id)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
