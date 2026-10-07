import Foundation
import Testing

@testable import Ainkrad

@Suite("GlobTool")
@MainActor
struct GlobToolTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glob-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("src/A.swift"), atomically: true, encoding: .utf8)
        try "y".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return root
    }
    @Test func matchesSwiftFiles() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = GlobTool(rootProvider: { root })
        let r = try await tool.execute(.object(["pattern": .string("**/*.swift")]))
        #expect(r.content.contains("A.swift"))
        #expect(!r.content.contains("README.md"))
    }
    @Test func requiresPattern() async {
        let tool = GlobTool(rootProvider: { FileManager.default.temporaryDirectory })
        await #expect(throws: ToolError.self) { _ = try await tool.execute(.object([:])) }
    }
    @Test func permissionIsRead() {
        #expect(GlobTool(rootProvider: { FileManager.default.temporaryDirectory }).permission == .read)
    }
}
