import AinkradAppKit
import Foundation

/// Host-owned aggregator of per-plugin context sources. Each plugin publishes
/// ONLY its own snapshot (via its scoped HostServices.context); the host reads
/// across all apps here. Keyed by an opaque token so sources can unregister.
@MainActor
@Observable
public final class AgentContextRegistryHub {
    private struct Entry {
        let appID: String
        let source: @MainActor () -> AgentContextSnapshot?
    }
    private var entries: [PluginContextToken: Entry] = [:]

    public init() {}

    public func register(appID: String, _ source: @escaping @MainActor () -> AgentContextSnapshot?)
        -> PluginContextToken
    {
        let token = PluginContextToken()
        entries[token] = Entry(appID: appID, source: source)
        return token
    }

    public func remove(_ token: PluginContextToken) { entries[token] = nil }

    public func allSnapshots() -> [AgentContextSnapshot] { entries.values.compactMap { $0.source() } }
}
