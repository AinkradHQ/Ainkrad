import AinkradHostRuntime
// Tests/AinkradTests/AgentToolRegistryDynamicTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentToolRegistry dynamic tools")
@MainActor
struct AgentToolRegistryDynamicTests {
    private struct StubTool: AgentTool {
        let name: String
        let description = "stub"
        let permission: ToolPermissionClass = .read
        var parametersSchema: JSONValue { .object(["type": .string("object")]) }
        func execute(_ input: JSONValue) async throws -> ToolResult {
            ToolResult(content: "ran \(name)", isError: false)
        }
    }

    @Test func dynamicToolsAreVisibleAndRunnable() async {
        var live: [any AgentTool] = []
        let registry = AgentToolRegistry(
            tools: [StubTool(name: "static_a")],
            dynamicTools: { live })
        #expect(registry.tool(named: "mcp/x/y") == nil)
        live = [StubTool(name: "mcp/x/y")]
        #expect(registry.tool(named: "mcp/x/y") != nil)
        #expect(registry.schemas.contains { $0.name == "mcp/x/y" })
        let r = await registry.run(ToolCall(id: "1", name: "mcp/x/y", input: .object([:])))
        #expect(r.content == "ran mcp/x/y")
    }

    @Test func staticToolsWinOnNameCollision() {
        let registry = AgentToolRegistry(
            tools: [StubTool(name: "dup")],
            dynamicTools: { [StubTool(name: "dup")] })
        // Only one schema entry for "dup", and it resolves to a tool.
        #expect(registry.schemas.filter { $0.name == "dup" }.count == 1)
        #expect(registry.tool(named: "dup") != nil)
    }

    @Test func existingConstructorStillCompiles() {
        let registry = AgentToolRegistry(tools: [StubTool(name: "only")])
        #expect(registry.tool(named: "only") != nil)
    }
}
