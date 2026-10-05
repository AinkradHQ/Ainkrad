import AinkradHostRuntime
import Foundation
import Observation

/// Persisted choice of `web_search` provider. The API key itself never lives
/// here — it's Keychain-only via `SecretStore` (`BraveSearchBackend.secretID`).
struct WebSearchSettingsDocument: PersistableDocument {
    static let documentID = "websearch.settings"
    var provider: String = "brave"
    /// Base URL of the SearXNG instance for the keyless `searxng` provider.
    /// Not a credential, so it lives in the document (unlike the Brave key,
    /// which is Keychain-only). Empty means the SearXNG backend is unconfigured.
    var searxngURL: String = ""
}

/// Backs the Sage Settings WEB section's provider picker. Mirrors the
/// other `@Observable` settings stores (`VoiceSettingsStore`, `AppAppearanceStore`):
/// loads the persisted document at init, writes through on every setter call.
@MainActor
@Observable
final class WebSearchSettingsStore {
    private(set) var document: WebSearchSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(WebSearchSettingsDocument.self) ?? WebSearchSettingsDocument()
    }

    func setProvider(_ id: String) {
        document.provider = id
        persistence.save(document)
    }

    func setSearxngURL(_ url: String) {
        document.searxngURL = url
        persistence.save(document)
    }
}
