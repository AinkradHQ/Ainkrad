import AinkradAppKit
import AinkradHostRuntime
import Foundation

/// Injects a cheap index (name + description) of the active skills into the
/// agent's context each turn via `AgentContextRegistryHub`. Full instructions
/// stay on disk and load on demand through `use_skill` (progressive disclosure),
/// so a large skill library never bloats the prompt budget. Mirrors
/// `MemoryContextSource`'s pattern exactly: a pure function producing an
/// `AgentContextSnapshot?`, gated centrally by `AgentContextSettingsStore` via
/// `kind` (no per-source privacy check needed here).
enum SkillIndexContextSource {
    static let kind = "skills-index"

    @MainActor
    static func snapshot(from registry: SkillRegistry) -> AgentContextSnapshot? {
        let skills = registry.skills
        guard !skills.isEmpty else { return nil }
        // `registry.skills` is already sorted by name (see SkillRegistry.reload),
        // so the index is deterministic without re-sorting here.
        let list = skills.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        let body = """
            These skills encode reusable procedures. Only call the `use_skill` tool \
            when the user's request clearly matches one of the skills listed below, \
            and pass a name exactly as written here. Do NOT call it for greetings, \
            small talk, or general questions, and never invent a skill name that \
            isn't in this list — when in doubt, just answer directly.

            \(list)
            """
        return AgentContextSnapshot(kind: kind, title: "Available Skills", text: body)
    }
}
