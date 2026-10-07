import AinkradHostRuntime
// Tests/AinkradTests/MemoryWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("Memory wiring")
@MainActor
struct MemoryWiringTests {
    @Test func toolsAreRegistered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wire-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        let registry = AgentToolRegistry(tools: [MemoryWriteTool(service: svc), MemorySearchTool(service: svc)])
        #expect(registry.tool(named: "memory_write") != nil)
        #expect(registry.tool(named: "memory_search") != nil)
    }

    @Test func contextSourceRegistersAndProduces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wire2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        svc.write("hi", to: .user, provenance: .remember)
        let hub = AgentContextRegistryHub()
        _ = hub.register(appID: "host.memory") { MemoryContextSource.snapshot(from: svc) }
        #expect(hub.allSnapshots().contains { $0.kind == "assistant-memory" })
    }
}
