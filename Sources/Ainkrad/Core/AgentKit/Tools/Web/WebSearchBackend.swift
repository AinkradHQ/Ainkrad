import AinkradHostRuntime
import Foundation

struct WebSearchResult: Equatable, Sendable {
    let title: String
    let url: String
    let snippet: String
}

/// Pluggable search provider. `isConfigured == false` drives the graceful
/// "not configured" path in `WebSearchTool` (never an error result).
protocol WebSearchBackend: Sendable {
    var isConfigured: Bool { get }
    func search(query: String, count: Int) async throws -> [WebSearchResult]
}

/// Brave Search API backend. Key lives in the Keychain via `SecretStore`,
/// never in a document. Ships as the one concrete backend (Task 24 GAP spec).
struct BraveSearchBackend: WebSearchBackend {
    static let secretID = "websearch.brave.apiKey"
    private static let endpoint = URL(checkedLiteral: "https://api.search.brave.com/res/v1/web/search")
    // `SecretStore` is a plain (non-Sendable) `AnyObject` protocol; conformers
    // used here (KeychainSecretStore, InMemorySecretStore) are safe to hand
    // across the await boundary (same pattern as `SkillInstaller`/`http`).
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    private struct Payload: Decodable {
        struct Web: Decodable { let results: [Item] }
        struct Item: Decodable {
            let title: String
            let url: String
            let description: String?
        }
        let web: Web?
    }

    func search(query: String, count: Int) async throws -> [WebSearchResult] {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Web search is not configured.")
        }
        var comps = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        comps?.queryItems = [.init(name: "q", value: query), .init(name: "count", value: String(count))]
        guard let url = comps?.url else {
            throw ToolError.message("web_search could not build the Brave request URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("web_search got HTTP \(response.statusCode).")
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.web?.results ?? []).prefix(count).map {
            WebSearchResult(title: $0.title, url: $0.url, snippet: $0.description ?? "")
        }
    }
}
