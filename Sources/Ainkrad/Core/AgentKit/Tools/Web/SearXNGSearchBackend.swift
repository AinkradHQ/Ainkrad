import AinkradHostRuntime
import Foundation

/// Keyless `web_search` backend backed by a SearXNG instance (self-hosted or
/// public). No API key or payment card — configuration is just the instance
/// base URL, persisted in `WebSearchSettingsDocument.searxngURL` (not a secret,
/// since it is not a credential). `isConfigured == false` when no URL is set,
/// which drives the graceful "not configured" path in `WebSearchTool`.
struct SearXNGSearchBackend: WebSearchBackend {
    /// Base URL of the SearXNG instance, e.g. `https://searx.example.org`.
    /// Empty string means unconfigured.
    let instanceURL: String
    let http: DataHTTPClient

    var isConfigured: Bool { !normalizedBase.isEmpty }

    /// Trims whitespace and any trailing slash so `base + "/search"` is well-formed.
    private var normalizedBase: String {
        var s = instanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private struct Payload: Decodable {
        struct Item: Decodable {
            let title: String?
            let url: String?
            let content: String?
        }
        let results: [Item]
    }

    func search(query: String, count: Int) async throws -> [WebSearchResult] {
        let base = normalizedBase
        guard !base.isEmpty else { throw ToolError.message("Web search is not configured.") }
        guard var comps = URLComponents(string: base + "/search") else {
            throw ToolError.message("SearXNG instance URL is invalid.")
        }
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { throw ToolError.message("SearXNG instance URL is invalid.") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            // A 403 here usually means the instance has the JSON API disabled.
            throw ToolError.message("web_search got HTTP \(response.statusCode) from SearXNG.")
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.results.prefix(count).map {
            WebSearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.content ?? "")
        }
    }
}
