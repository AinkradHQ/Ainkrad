import AinkradAppKit
import Foundation

/// The per-app `PluginContextRegistry` handed to one plugin's HostServices.
/// Forwards to the shared host hub, tagging registrations with this app's id.
@MainActor
public struct HostContextRegistry: PluginContextRegistry {
    let appID: String
    unowned let hub: AgentContextRegistryHub

    public init(appID: String, hub: AgentContextRegistryHub) {
        self.appID = appID
        self.hub = hub
    }

    public func register(_ source: @escaping @MainActor () -> AgentContextSnapshot?) -> PluginContextToken {
        hub.register(appID: appID, source)
    }
    public func remove(_ token: PluginContextToken) { hub.remove(token) }
}
