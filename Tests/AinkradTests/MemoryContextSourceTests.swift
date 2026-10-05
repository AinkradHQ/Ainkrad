import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryContextSource")
@MainActor
struct MemoryContextSourceTests {
    private func service() throws -> (MemoryService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-\(UUID().uuidString)")
        return (try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore()), root)
    }

    @Test func nilWhenEmpty() throws {
        let (svc, root) = try service()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(MemoryContextSource.snapshot(from: svc) == nil)
    }

    @Test func includesNonEmptyFiles() throws {
        let (svc, root) = try service()
        defer { try? FileManager.default.removeItem(at: root) }
        svc.write("uses automotiveai email", to: .user, provenance: .remember)
        let snap = MemoryContextSource.snapshot(from: svc)
        #expect(snap?.kind == "assistant-memory")
        #expect(snap?.text.contains("automotiveai") == true)
        #expect(snap?.text.contains("USER.md") == true)
    }
}
