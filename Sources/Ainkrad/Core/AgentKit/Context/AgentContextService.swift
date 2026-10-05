import AinkradAppKit
import AinkradHostRuntime
import Foundation

/// Assembles the host's workspace-context block for the agent from
/// `AgentContextRegistryHub` snapshots, honoring per-kind privacy toggles
/// from `AgentContextSettingsStore` and bounding each source's size so one
/// noisy plugin can't blow the prompt budget.
@MainActor
struct AgentContextService {
    /// Max characters of a single snapshot's `text` kept in the assembled
    /// context; anything beyond this is tail-dropped with a marker.
    static let perSourceCharBudget = 8000
    private static let truncationMarker = "…[truncated]"

    let hub: AgentContextRegistryHub
    let settings: AgentContextSettingsStore

    init(hub: AgentContextRegistryHub, settings: AgentContextSettingsStore) {
        self.hub = hub
        self.settings = settings
    }

    func assembleContext() -> String {
        let sections = hub.allSnapshots()
            .filter { settings.isEnabled(kind: $0.kind) }
            .map(renderSection)

        guard !sections.isEmpty else { return "" }

        let body = sections.joined(separator: "\n\n")
        return "<workspace_context>\n\(body)\n</workspace_context>"
    }

    private func renderSection(_ snapshot: AgentContextSnapshot) -> String {
        "## \(snapshot.title)\n\(truncated(snapshot.text))"
    }

    private func truncated(_ text: String) -> String {
        guard text.count > Self.perSourceCharBudget else { return text }
        let prefix = String(text.prefix(Self.perSourceCharBudget))
        return prefix + Self.truncationMarker
    }
}
