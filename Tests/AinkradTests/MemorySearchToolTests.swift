import AinkradHostRuntime
// Tests/AinkradTests/MemorySearchToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("MemorySearchTool")
@MainActor
struct MemorySearchToolTests {
    private func make() throws -> (MemorySearchTool, MemoryService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ms-\(UUID().uuidString)")
        let svc = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        return (MemorySearchTool(service: svc), svc, root)
    }

    @Test func permissionIsReadClass() throws {
        let (tool, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(tool.permission == .read)
    }

    @Test func findsStoredFact() async throws {
        let (tool, svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.write("the deploy script lives in scripts/release.sh", to: .memory, provenance: .agent)
        let r = try await tool.execute(.object(["query": .string("deploy script")]))
        #expect(!r.isError)
        #expect(r.content.contains("release.sh"))
    }

    @Test func reportsNoResults() async throws {
        let (tool, _, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        let r = try await tool.execute(.object(["query": .string("nonexistent")]))
        #expect(r.content.contains("No memory"))
    }

    @Test func respectsLimitParameter() async throws {
        let (tool, svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.write("shared token alpha one", to: .memory, provenance: .agent)
        svc.write("shared token alpha two", to: .user, provenance: .agent)
        let r = try await tool.execute(
            .object([
                "query": .string("alpha"), "limit": .number(1),
            ]))
        #expect(r.content.split(separator: "\n").count == 1)
    }

    @Test func nonFiniteLimitDoesNotTrap() async throws {
        let (tool, svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.write("shared token beta one", to: .memory, provenance: .agent)
        await #expect(throws: Never.self) {
            let r = try await tool.execute(
                .object([
                    "query": .string("beta"), "limit": .number(Double.nan),
                ]))
            #expect(r.content.contains("beta"))
        }
    }

    @Test func outOfRangeLimitDoesNotTrap() async throws {
        let (tool, svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.write("shared token gamma one", to: .memory, provenance: .agent)
        await #expect(throws: Never.self) {
            let r = try await tool.execute(
                .object([
                    "query": .string("gamma"), "limit": .number(1e300),
                ]))
            #expect(r.content.contains("gamma"))
        }
    }
}
