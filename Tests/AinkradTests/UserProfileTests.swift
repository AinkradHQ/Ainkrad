import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("UserProfile")
@MainActor
struct UserProfileTests {
    private func make() -> (UserProfileStore, MemoryStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("up-\(UUID().uuidString)")
        let mem = MemoryStore(paths: MemoryPaths(root: root))
        let store = UserProfileStore(persistence: InMemoryPersistenceStore(), memory: mem)
        return (store, mem, root)
    }

    @Test func setPersistsAndProjectsToUserMd() {
        let (store, mem, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.set("automotiveai", for: "employer")
        #expect(store.all()["employer"] == "automotiveai")
        #expect(mem.read(.user).contains("employer: automotiveai"))
    }

    /// Settings-pane clearing (Fix 2): an emptied field must remove the fact
    /// entirely, not leave a dangling `- role: ` line in USER.md.
    @Test func removeClearsFactAndUserMdLine() {
        let (store, mem, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        store.set("Engineer", for: "role")
        #expect(store.all()["role"] == "Engineer")
        #expect(mem.read(.user).contains("- role: Engineer"))

        store.remove("role")

        #expect(store.all()["role"] == nil)
        #expect(!mem.read(.user).contains("role"))
    }
}
