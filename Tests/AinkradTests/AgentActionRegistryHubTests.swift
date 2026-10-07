import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("AgentActionRegistryHub")
struct AgentActionRegistryHubTests {
    @Test("invoke runs the handler registered for the actionID")
    func invokeRuns() async {
        let hub = AgentActionRegistryHub()
        _ = hub.register(appID: "terminal", actionID: "terminal.echo") { json in
            AgentActionResult(text: "echoed:\(json)", isError: false)
        }
        let result = await hub.invoke(actionID: "terminal.echo", input: "hi")
        #expect(result == AgentActionResult(text: "echoed:hi", isError: false))
    }

    @Test("invoke returns nil when no handler is registered for the actionID")
    func invokeUnknown() async {
        let hub = AgentActionRegistryHub()
        let result = await hub.invoke(actionID: "gitmage.git_op", input: "{}")
        #expect(result == nil)
    }

    @Test("remove unregisters the handler")
    func removeUnregisters() async {
        let hub = AgentActionRegistryHub()
        let token = hub.register(appID: "g", actionID: "gitmage.git_op") { _ in
            AgentActionResult(text: "ok", isError: false)
        }
        hub.remove(token)
        let result = await hub.invoke(actionID: "gitmage.git_op", input: "{}")
        #expect(result == nil)
    }

    @Test("HostActionRegistry forwards to the hub tagging its appID")
    func forwarderInvokes() async {
        let hub = AgentActionRegistryHub()
        let reg = HostActionRegistry(appID: "terminal", hub: hub)
        _ = reg.register(actionID: "terminal.echo") { _ in
            AgentActionResult(text: "via-forwarder", isError: false)
        }
        let result = await hub.invoke(actionID: "terminal.echo", input: "{}")
        #expect(result == AgentActionResult(text: "via-forwarder", isError: false))
    }
}
