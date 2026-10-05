import AinkradAppKit
import Foundation
import Observation

/// Host-owned aggregator of per-plugin gated action handlers. Each plugin
/// registers ONLY its own handlers (via its scoped HostServices.actions); the
/// host invokes across all apps here. Keyed by an opaque token so handlers can
/// unregister. The write-side sibling of `AgentContextRegistryHub`.
@MainActor
@Observable
public final class AgentActionRegistryHub {
    private struct Entry {
        let appID: String
        let actionID: String
        let handler: @MainActor (String) async -> AgentActionResult
    }
    private var entries: [AgentActionToken: Entry] = [:]

    public init() {}

    public func register(
        appID: String, actionID: String,
        handler: @escaping @MainActor (String) async -> AgentActionResult
    ) -> AgentActionToken {
        let token = AgentActionToken()
        entries[token] = Entry(appID: appID, actionID: actionID, handler: handler)
        return token
    }

    public func remove(_ token: AgentActionToken) { entries[token] = nil }

    /// Invoke the handler registered for `actionID`. Returns nil when none is
    /// registered (e.g. the owning plugin isn't installed/open). First match
    /// wins — actionIDs are namespaced ("terminal.echo", "gitmage.git_op") so a
    /// collision across apps is not expected.
    public func invoke(actionID: String, input: String) async -> AgentActionResult? {
        guard let entry = entries.values.first(where: { $0.actionID == actionID }) else { return nil }
        return await entry.handler(input)
    }
}
