import AinkradHostRuntime
import Foundation
import Observation

/// Persisted, observable CRUD over `ToolHook`s (mirrors `AgentConfigStore`'s
/// persistence pattern: load on init, save on every mutation).
@MainActor
@Observable
final class ToolHooksStore {
    private(set) var hooks: [ToolHook]
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.hooks = persistence.load(ToolHooksDocument.self)?.hooks ?? []
    }

    func add(_ hook: ToolHook) {
        hooks.append(hook)
        save()
    }

    func update(_ hook: ToolHook) {
        guard let idx = hooks.firstIndex(where: { $0.id == hook.id }) else { return }
        hooks[idx] = hook
        save()
    }

    func remove(id: UUID) {
        hooks.removeAll { $0.id == id }
        save()
    }

    /// Enabled hooks for `event` whose `match` glob matches `toolName`, in
    /// insertion order (deterministic execution order).
    func hooks(for event: ToolHookEvent, toolName: String) -> [ToolHook] {
        hooks.filter {
            $0.enabled && $0.event == event && ToolHookMatcher.matches(pattern: $0.match, toolName: toolName)
        }
    }

    private func save() { persistence.save(ToolHooksDocument(hooks: hooks)) }
}
