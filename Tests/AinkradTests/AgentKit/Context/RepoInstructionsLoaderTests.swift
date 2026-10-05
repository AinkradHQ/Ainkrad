import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@MainActor @Suite struct RepoInstructionsLoaderTests {
    private func makeRepo(_ body: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: base.appendingPathComponent("CLAUDE.md"))
        return base
    }

    @Test func snapshotLabelsAndIncludesContent() throws {
        let root = try makeRepo("# House rules\nUse tabs.")
        let loader = RepoInstructionsLoader(root: root)
        let snap = try #require(loader.snapshot())
        #expect(snap.kind == "repo-instructions")
        #expect(snap.title == "Repository Instructions")
        #expect(snap.text.contains("CLAUDE.md"))
        #expect(snap.text.contains("Use tabs."))
    }

    @Test func nilWhenNoInstructionFiles() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let loader = RepoInstructionsLoader(root: empty, perFileCharCap: 6000)
        #expect(loader.snapshot() == nil)
    }

    @Test func perFileCapTruncates() throws {
        let root = try makeRepo(String(repeating: "x", count: 10_000))
        let loader = RepoInstructionsLoader(root: root, perFileCharCap: 100)
        let snap = try #require(loader.snapshot())
        #expect(snap.text.contains("…[truncated]"))
    }

    @Test func picksUpEditedFileOnNextPoll() throws {
        let root = try makeRepo("v1 rules")
        let loader = RepoInstructionsLoader(root: root)
        _ = loader.snapshot()
        try Data("v2 rules".utf8).write(to: root.appendingPathComponent("CLAUDE.md"))
        // bump mtime explicitly so the cache invalidates deterministically
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: root.appendingPathComponent("CLAUDE.md").path)
        let snap = try #require(loader.snapshot())
        #expect(snap.text.contains("v2 rules"))
    }
}
