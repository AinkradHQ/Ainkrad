// Tests/AinkradTests/WorkspaceFileIndexTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("WorkspaceFileIndex")
@MainActor
struct WorkspaceFileIndexTests {
    private func tree() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wfi-\(UUID().uuidString)")
        let fm = FileManager.default
        try? fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try? "".write(to: root.appendingPathComponent("src/AgentSession.swift"), atomically: true, encoding: .utf8)
        try? "".write(to: root.appendingPathComponent("src/ModelRouter.swift"), atomically: true, encoding: .utf8)
        try? "".write(to: root.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func fuzzyFindsFile() {
        let root = tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let idx = WorkspaceFileIndex(root: root)
        idx.refreshSynchronously()
        let hits = idx.search("agsess")
        #expect(hits.first?.name == "AgentSession.swift")
    }

    @Test func skipsGitDirectory() {
        let root = tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let idx = WorkspaceFileIndex(root: root)
        idx.refreshSynchronously()
        #expect(idx.search("config").isEmpty)
    }

    @Test func emptyQueryReturnsNothing() {
        let root = tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let idx = WorkspaceFileIndex(root: root)
        idx.refreshSynchronously()
        #expect(idx.search("").isEmpty)
    }
}
