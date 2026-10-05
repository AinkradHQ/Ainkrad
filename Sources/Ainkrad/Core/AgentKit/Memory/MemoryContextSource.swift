import AinkradAppKit
import AinkradHostRuntime
import Foundation

/// Publishes the always-loaded memory set (USER.md / MEMORY.md / AGENTS.md,
/// size-capped by `MemoryStore.alwaysLoadedSet`) as a single workspace-context
/// snapshot, so the agent has it from session start. Mirrors the Terminal /
/// Git Mage context-source pattern: a pure function producing an
/// `AgentContextSnapshot?`, registered on `AgentContextRegistryHub` and gated
/// by `AgentContextSettingsStore` via its `kind`.
enum MemoryContextSource {
    static let kind = "assistant-memory"

    @MainActor
    static func snapshot(from service: MemoryService) -> AgentContextSnapshot? {
        let loaded = service.alwaysLoaded()
        guard !loaded.isEmpty else { return nil }
        let body =
            loaded
            .map { "### \($0.0.rawValue)\n\($0.1)" }
            .joined(separator: "\n\n")
        return AgentContextSnapshot(kind: kind, title: "Sage Memory", text: body)
    }
}
