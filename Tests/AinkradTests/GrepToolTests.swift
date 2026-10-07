import Foundation
import Testing

@testable import Ainkrad

@Suite("GrepTool")
@MainActor
struct GrepToolTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "let x = 1\nfunc foo() {}\n".write(
            to: root.appendingPathComponent("A.swift"),
            atomically: true, encoding: .utf8)
        return root
    }
    @Test func findsMatchesWithLocation() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = GrepTool(rootProvider: { root })
        let r = try await tool.execute(.object(["pattern": .string("func +\\w+")]))
        #expect(!r.isError)
        #expect(r.content.contains("A.swift"))
        #expect(r.content.contains(":2:"))  // line number of `func foo`
        #expect(r.content.contains("func foo"))
    }
    @Test func caseInsensitive() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = GrepTool(rootProvider: { root })
        let r = try await tool.execute(
            .object([
                "pattern": .string("FOO"),
                "caseInsensitive": .bool(true),
            ]))
        #expect(r.content.contains("foo"))
    }
    @Test func invalidRegexErrors() async {
        let tool = GrepTool(rootProvider: { FileManager.default.temporaryDirectory })
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object(["pattern": .string("(")]))
        }
    }
    @Test func permissionIsRead() {
        #expect(GrepTool(rootProvider: { FileManager.default.temporaryDirectory }).permission == .read)
    }
    @Test func outOfRangeMaxMatchesDoesNotCrash() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = GrepTool(rootProvider: { root })
        let r = try await tool.execute(
            .object([
                "pattern": .string("func"),
                "maxMatches": .number(1e309),
            ]))  // +inf
        #expect(!r.isError)
    }
}
