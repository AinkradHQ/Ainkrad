import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("WebSearchSettingsStore")
@MainActor
struct WebSearchSettingsStoreTests {
    @Test func persistsProviderChoice() {
        let p = InMemoryPersistenceStore()
        let store = WebSearchSettingsStore(persistence: p)
        store.setProvider("searxng")
        #expect(WebSearchSettingsStore(persistence: p).document.provider == "searxng")
    }

    @Test func persistsSearxngURL() {
        let p = InMemoryPersistenceStore()
        let store = WebSearchSettingsStore(persistence: p)
        store.setSearxngURL("https://searx.example.org")
        #expect(WebSearchSettingsStore(persistence: p).document.searxngURL == "https://searx.example.org")
    }
}
