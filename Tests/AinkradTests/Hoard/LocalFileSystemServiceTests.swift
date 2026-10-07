import Foundation
import Testing

@testable import Ainkrad

@Suite("LocalFileSystemService")
struct LocalFileSystemServiceTests {
    /// Builds a throwaway directory tree and hands back its root.
    private func makeTempTree() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("files-tests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("lists directory contents with metadata")
    func listsContents() throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = LocalFileSystemService()
        let entries = try service.contents(of: root).sorted { $0.name < $1.name }

        #expect(entries.map(\.name) == [".hidden", "a.txt", "sub"])
        #expect(entries.first { $0.name == "sub" }?.isDirectory == true)
        #expect(entries.first { $0.name == "a.txt" }?.isDirectory == false)
        #expect(entries.first { $0.name == "a.txt" }?.size == 5)
        #expect(entries.first { $0.name == ".hidden" }?.isHidden == true)
        #expect(entries.first { $0.name == "a.txt" }?.isHidden == false)
    }

    @Test("throws for a directory that does not exist")
    func throwsForMissing() {
        let service = LocalFileSystemService()
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try service.contents(of: missing) }
    }

    @Test("reports directory-ness and existence")
    func predicates() throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = LocalFileSystemService()
        #expect(service.isDirectory(root.appendingPathComponent("sub")))
        #expect(!service.isDirectory(root.appendingPathComponent("a.txt")))
        #expect(service.exists(root.appendingPathComponent("a.txt")))
        #expect(!service.exists(root.appendingPathComponent("nope.txt")))
    }
}
