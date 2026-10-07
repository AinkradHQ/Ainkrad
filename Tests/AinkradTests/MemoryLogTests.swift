import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryLog")
@MainActor
struct MemoryLogTests {
    private func make() -> (MemoryLogStore, MemoryStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString)")
        let mem = MemoryStore(paths: MemoryPaths(root: root))
        return (MemoryLogStore(persistence: InMemoryPersistenceStore(), memory: mem), mem, root)
    }

    @Test func recordsEntry() {
        let (log, _, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        log.record(file: .memory, provenance: .agent, addedText: "x", priorSnapshot: "")
        #expect(log.entries().count == 1)
        #expect(log.entries().first?.provenance == .agent)
    }

    @Test func undoRestoresPriorSnapshot() {
        let (log, mem, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        mem.write("old", to: .memory)
        log.record(file: .memory, provenance: .agent, addedText: "new", priorSnapshot: "old")
        mem.write("old\nnew", to: .memory)
        let id = log.entries().first!.id
        log.undo(id)
        #expect(mem.read(.memory) == "old")
        #expect(log.entries().isEmpty)
    }

    @Test func undoOfFirstWriteRestoresEmpty() {
        let (log, mem, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        let priorSnapshot = mem.read(.memory)
        #expect(priorSnapshot == "")
        mem.write("first content", to: .memory)
        log.record(file: .memory, provenance: .agent, addedText: "first content", priorSnapshot: priorSnapshot)
        let id = log.entries().first!.id
        log.undo(id)
        #expect(mem.read(.memory) == "")
    }
}
