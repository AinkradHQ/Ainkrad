import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ToolHooksStore")
@MainActor
struct ToolHooksStoreTests {
    @Test func addPersistsAndFiltersByEventAndName() {
        let persistence = InMemoryPersistenceStore()
        let store = ToolHooksStore(persistence: persistence)
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .postToolUse, match: "edit_file",
                command: "echo formatted", timeoutSeconds: 10))
        store.add(
            ToolHook(
                id: UUID(), enabled: false, event: .postToolUse, match: "edit_file",
                command: "echo disabled", timeoutSeconds: 10))
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .preToolUse, match: "*",
                command: "echo pre", timeoutSeconds: 10))

        let post = store.hooks(for: .postToolUse, toolName: "edit_file")
        #expect(post.count == 1)  // disabled one excluded
        #expect(post.first?.command == "echo formatted")
        #expect(store.hooks(for: .preToolUse, toolName: "read_file").count == 1)  // `*` matches

        // Reload proves persistence.
        let reloaded = ToolHooksStore(persistence: persistence)
        #expect(reloaded.hooks.count == 3)
    }

    @Test func removeDropsAHook() {
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        let hook = ToolHook(id: UUID(), enabled: true, event: .preToolUse, match: "*", command: "x", timeoutSeconds: 5)
        store.add(hook)
        store.remove(id: hook.id)
        #expect(store.hooks.isEmpty)
    }
}
