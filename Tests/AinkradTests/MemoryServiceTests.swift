import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryService")
@MainActor
struct MemoryServiceTests {
    private func make() throws -> (MemoryService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString)")
        return (try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore()), root)
    }

    @Test func writeIndexesAndLogs() throws {
        let (svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.write("prefers dark mode", to: .memory, provenance: .agent)
        #expect(svc.search("dark", limit: 10).count == 1)
        #expect(svc.log.entries().count == 1)
    }

    @Test func rebuildReindexesFromFiles() throws {
        let (svc, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.store.write("findable content", to: .agents)  // direct edit, bypasses write()
        svc.rebuildIndex()
        #expect(svc.search("findable", limit: 10).count == 1)
    }
}
