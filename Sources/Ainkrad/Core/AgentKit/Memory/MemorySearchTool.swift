import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Memory/MemorySearchTool.swift
import Foundation

struct MemorySearchTool: AgentTool {
    let service: MemoryService

    let name = "memory_search"
    let description = """
        Search the assistant's long-term memory (and past-session summaries) for relevant facts. \
        Call this before assuming you don't know something about the user or project.
        """
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("What to look for in memory."),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Max results to return (1-50, default 20)."),
                ]),
            ]),
            "required": .array([.string("query")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            throw ToolError.message("memory_search requires a non-empty \"query\".")
        }
        // JSONValue has no .int case — all numbers are .number(Double).
        var limit = 20
        if case .number(let n)? = input["limit"], n.isFinite { limit = Int(min(max(n, 1), 50)) }
        let hits = service.search(query, limit: limit)
        guard !hits.isEmpty else { return ToolResult(content: "No memory found.", isError: false) }
        let body = hits.map { "- [\($0.source)] \($0.snippet)" }.joined(separator: "\n")
        return ToolResult(content: body, isError: false)
    }
}
