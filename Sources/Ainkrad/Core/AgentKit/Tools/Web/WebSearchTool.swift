import AinkradHostRuntime
import Foundation

/// Wraps a `WebSearchBackend` as a read-class `AgentTool`. Falls back to a
/// graceful (non-error) "not configured" message rather than throwing, since
/// missing search credentials is an expected, user-actionable state.
struct WebSearchTool: AgentTool {
    let backend: any WebSearchBackend

    let name = "web_search"
    let description = "Search the web and return a list of results (title, url, snippet)."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query."),
                ]),
                "count": .object([
                    "type": .string("number"),
                    "description": .string("Max results (1–10, default 5)."),
                ]),
            ]),
            "required": .array([.string("query")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            throw ToolError.message("web_search requires a non-empty \"query\".")
        }
        guard backend.isConfigured else {
            return ToolResult(
                content: "Web search is not configured. Add a search API key in Settings → Sage → Web.",
                isError: false)
        }
        var count = 5
        // Clamp in Double space BEFORE `Int(_:)` — `Int(.nan)`/`Int(1e300)` trap
        // (uncatchable), and `count` is model-controlled. `n >= 1` also rejects
        // NaN, so an out-of-range value keeps the default 5. Mirrors WebFetchTool.
        if case .number(let n)? = input["count"], n >= 1 { count = min(Int(min(n, 10.0)), 10) }
        let results = try await backend.search(query: query, count: count)
        if results.isEmpty { return ToolResult(content: "No results for \"\(query)\".", isError: false) }
        let body = results.enumerated().map { i, r in
            "\(i + 1). \(r.title)\n\(r.url)\n\(r.snippet)"
        }.joined(separator: "\n\n")
        return ToolResult(content: body, isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Web search", summary: input["query"]?.stringValue ?? "?", diff: nil)
    }
}
