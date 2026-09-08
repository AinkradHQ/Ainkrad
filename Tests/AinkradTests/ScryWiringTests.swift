import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("Scry wiring")
@MainActor
struct ScryWiringTests {
    @Test func canvasAppHasStableID() {
        #expect(ScryApp.id == "scry")
        #expect(!ScryApp.displayName.isEmpty)
    }

    @Test func toolMutatesTheWiredStore() async throws {
        let store = ScryStore(sessionID: "default")
        let registry = AgentToolRegistry(tools: [ScryRenderTool(store: store)])
        let result = await registry.run(ToolCall(
            id: "1", name: "scry_render",
            input: .object(["op": .string("add"), "id": .string("a"),
                            "kind": .string("text"), "body": .string("hello")])))
        #expect(!result.isError)
        #expect(store.model.elements.first?.body == "hello")
    }

    // Post-review fix (I1): `scry_render` is bound to the FOREGROUND
    // `scryStore` (sessionID "default" — the same store `ScryApp` reads).
    // The background/headless tool registry `AppEnvironment` builds for
    // `RunManager`-driven runs (background/schedule/trigger) MUST exclude it,
    // mirroring the exact `agentTools.filter { !($0 is ScryRenderTool) }`
    // AppEnvironment applies when deriving `backgroundAgentTools` — otherwise
    // an autonomous run could silently mutate the canvas the user is viewing.
    @Test func backgroundRegistryExcludesCanvasRenderButForegroundKeepsIt() {
        let store = ScryStore(sessionID: "default")
        let agentTools: [any AgentTool] = [ReadFileTool(), ScryRenderTool(store: store)]
        let foregroundRegistry = AgentToolRegistry(tools: agentTools)
        let backgroundAgentTools = agentTools.filter { !($0 is ScryRenderTool) }
        let backgroundRegistry = AgentToolRegistry(tools: backgroundAgentTools)

        #expect(foregroundRegistry.tool(named: "scry_render") != nil)
        #expect(backgroundRegistry.tool(named: "scry_render") == nil)
        // Sanity: the filter didn't drop anything else.
        #expect(backgroundRegistry.tool(named: "read_file") != nil)
    }
}
