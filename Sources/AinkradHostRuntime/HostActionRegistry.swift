import AinkradAppKit
import Foundation

/// The per-app `AgentActionProvider` handed to one plugin's HostServices.
/// Forwards to the shared host hub, tagging registrations with this app's id.
@MainActor
public struct HostActionRegistry: AgentActionProvider {
    let appID: String
    unowned let hub: AgentActionRegistryHub

    public init(appID: String, hub: AgentActionRegistryHub) {
        self.appID = appID
        self.hub = hub
    }

    public func register(
        actionID: String,
        handler: @escaping @MainActor (String) async -> AgentActionResult
    ) -> AgentActionToken {
        hub.register(appID: appID, actionID: actionID, handler: handler)
    }
    public func remove(_ token: AgentActionToken) { hub.remove(token) }
}
