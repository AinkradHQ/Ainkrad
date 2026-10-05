import AinkradHostRuntime
import Foundation

/// Dispatches `web_search` to the backend the user selected in Settings, read
/// live from the persisted `WebSearchSettingsDocument.provider` on every call —
/// so switching provider takes effect without an app relaunch. `PersistenceStore`
/// is a plain (non-Sendable) `AnyObject`; `nonisolated(unsafe)` mirrors the
/// `BraveSearchBackend.secrets` precedent (its `load` is a synchronous read and
/// the conformers used here — `UserDefaults`-backed and in-memory — are safe to
/// touch across the await boundary).
struct RoutingWebSearchBackend: WebSearchBackend {
    let persistence: PersistenceStore
    let brave: BraveSearchBackend
    let duckduckgo: DuckDuckGoSearchBackend
    /// HTTP client used to build the SearXNG backend on demand (its instance URL
    /// is read live from the document, so it is constructed per call).
    let searxngHTTP: DataHTTPClient

    private var document: WebSearchSettingsDocument {
        persistence.load(WebSearchSettingsDocument.self) ?? WebSearchSettingsDocument()
    }

    /// The backend for the currently-persisted provider (defaults to Brave).
    private var active: any WebSearchBackend {
        let doc = document
        switch doc.provider {
        case "searxng": return SearXNGSearchBackend(instanceURL: doc.searxngURL, http: searxngHTTP)
        case "duckduckgo": return duckduckgo
        default: return brave
        }
    }

    var isConfigured: Bool { active.isConfigured }

    func search(query: String, count: Int) async throws -> [WebSearchResult] {
        try await active.search(query: query, count: count)
    }
}
