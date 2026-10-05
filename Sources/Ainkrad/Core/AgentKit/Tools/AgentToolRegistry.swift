// Sources/Ainkrad/Core/AgentKit/Tools/AgentToolRegistry.swift
import Foundation

@MainActor
final class AgentToolRegistry {
    private let staticTools: [String: any AgentTool]
    private let staticOrder: [String]
    /// Live provider for tools discovered after construction (e.g. MCP adapters).
    /// Read on every access so connecting/disconnecting a server takes effect
    /// without rebuilding the registry (the registry is otherwise immutable).
    private let dynamicTools: @MainActor () -> [any AgentTool]

    init(
        tools: [any AgentTool],
        dynamicTools: @escaping @MainActor () -> [any AgentTool] = { [] }
    ) {
        var map: [String: any AgentTool] = [:]
        var order: [String] = []
        for tool in tools where map[tool.name] == nil {
            map[tool.name] = tool
            order.append(tool.name)
        }
        self.staticTools = map
        self.staticOrder = order
        self.dynamicTools = dynamicTools
    }

    /// Static tools first (stable order), then dynamic tools whose names don't
    /// collide with a static tool (static wins).
    private func resolved() -> (map: [String: any AgentTool], order: [String]) {
        var map = staticTools
        var order = staticOrder
        for tool in dynamicTools() where map[tool.name] == nil {
            map[tool.name] = tool
            order.append(tool.name)
        }
        return (map, order)
    }

    func tool(named name: String) -> (any AgentTool)? { resolved().map[name] }

    var schemas: [AgentToolSchema] {
        let r = resolved()
        return r.order.compactMap { r.map[$0]?.schema }
    }

    /// Executes a call, mapping any throw or unknown-tool into an error result
    /// (the loop feeds this back to the agent as a `tool_result` with `is_error`).
    func run(_ call: ToolCall) async -> ToolResult {
        guard let tool = resolved().map[call.name] else {
            return ToolResult(content: "Unknown tool: \(call.name)", isError: true)
        }
        do {
            return try await tool.execute(call.input)
        } catch let ToolError.message(m) {
            return ToolResult(content: m, isError: true)
        } catch {
            return ToolResult(content: error.localizedDescription, isError: true)
        }
    }
}
