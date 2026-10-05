import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryUIViewModel")
@MainActor
struct MemoryUIViewModelTests {
    private func make() throws -> (MemoryUIViewModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)")
        let service = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        return (MemoryUIViewModel(service: service), root)
    }

    @Test func loadsDraftsFromDiskOnInit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        service.store.write("existing agents rule", to: .agents)
        let vm = MemoryUIViewModel(service: service)
        #expect(vm.draft(for: .agents) == "existing agents rule")
        #expect(vm.draft(for: .memory) == "")
    }

    @Test func saveWritesLogsAsEditAndReindexes() throws {
        let (vm, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        vm.setDraft("the user prefers dark mode", for: .user)
        vm.save(.user)

        #expect(vm.service.store.read(.user) == "the user prefers dark mode")
        #expect(vm.logEntries.count == 1)
        #expect(vm.logEntries.first?.provenance == .edit)
        #expect(vm.logEntries.first?.file == MemoryFile.user.rawValue)
        #expect(vm.service.search("dark mode", limit: 10).count == 1)
    }

    @Test func saveIsNoOpWhenDraftUnchanged() throws {
        let (vm, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        vm.save(.memory)  // draft == disk content ("") — nothing to persist
        #expect(vm.logEntries.isEmpty)
    }

    @Test func hasUnsavedChangesTracksDraftVsDisk() throws {
        let (vm, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(vm.hasUnsavedChanges(.memory) == false)
        vm.setDraft("a new fact", for: .memory)
        #expect(vm.hasUnsavedChanges(.memory) == true)
        vm.save(.memory)
        #expect(vm.hasUnsavedChanges(.memory) == false)
    }

    @Test func undoRestoresPriorSnapshotAndRefreshesDrafts() throws {
        let (vm, root) = try make()
        defer { try? FileManager.default.removeItem(at: root) }
        vm.setDraft("first edit", for: .agents)
        vm.save(.agents)
        vm.setDraft("second edit", for: .agents)
        vm.save(.agents)
        #expect(vm.logEntries.count == 2)

        let latest = vm.logEntries.first!  // entries() sorts newest-first
        #expect(latest.addedText == "second edit")
        vm.undo(latest.id)

        #expect(vm.service.store.read(.agents) == "first edit")
        #expect(vm.draft(for: .agents) == "first edit")  // refreshed, not stale
        #expect(vm.logEntries.count == 1)
    }
}
