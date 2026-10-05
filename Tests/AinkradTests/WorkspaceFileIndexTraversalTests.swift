import Foundation
import Testing

@testable import Ainkrad

@Suite("WorkspaceFileIndexTraversal")
@MainActor
struct WorkspaceFileIndexTraversalTests {
    @Test func fileURLsSkipsIgnoredDirs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wfi-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("src/a.swift"), atomically: true, encoding: .utf8)
        try "y".write(to: root.appendingPathComponent("node_modules/b.js"), atomically: true, encoding: .utf8)

        let urls = WorkspaceFileIndex.fileURLs(under: root)
        #expect(urls.contains { $0.lastPathComponent == "a.swift" })
        #expect(!urls.contains { $0.lastPathComponent == "b.js" })
        #expect(WorkspaceFileIndex.ignoredDirectories.contains("node_modules"))
    }
}
