import AinkradHostRuntime
// Tests/AinkradTests/MemoryWriteToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryWriteTool")
@MainActor
struct MemoryWriteToolTests {
    private func make() throws -> (MemoryWriteTool, MemoryService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mw-\(UUID().uuidString)")
        let svc = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        return (MemoryWriteTool(service: svc), svc, root)
    }

    @Test func writesToTargetFile() async throws {
        let (tool, svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        let r = try await tool.execute(.object(["target": .string("memory"), "content": .string("fact A")]))
        #expect(!r.isError)
        #expect(svc.store.read(.memory).contains("fact A"))
        #expect(svc.log.entries().first?.provenance == .agent)
    }

    @Test func permissionIsMemoryClass() throws {
        let (tool, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(tool.permission == .memory)
    }

    @Test func rejectsUnknownTarget() async throws {
        let (tool, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object(["target": .string("nope"), "content": .string("x")]))
        }
    }
}
