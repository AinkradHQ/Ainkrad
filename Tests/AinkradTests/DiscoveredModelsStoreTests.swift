import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("DiscoveredModelsStore")
@MainActor
struct DiscoveredModelsStoreTests {
    @Test("stores and reads a connection's discovered models; nil when never fetched")
    func roundTrip() {
        let persistence = InMemoryPersistenceStore()
        let store = DiscoveredModelsStore(persistence: persistence)
        let id = UUID()
        #expect(store.models(for: id) == nil)
        store.setModels(["nvidia/nemotron-nano-9b-v2:free", "openai/gpt-5"], for: id)
        #expect(store.models(for: id) == ["nvidia/nemotron-nano-9b-v2:free", "openai/gpt-5"])
    }

    @Test("persists across store instances (survives relaunch)")
    func persists() {
        let persistence = InMemoryPersistenceStore()
        let id = UUID()
        DiscoveredModelsStore(persistence: persistence).setModels(["a", "b"], for: id)
        let reloaded = DiscoveredModelsStore(persistence: persistence)
        #expect(reloaded.models(for: id) == ["a", "b"])
    }

    @Test("an authoritative empty live list replaces a previous list (provider now has no models)")
    func emptyIsAuthoritative() {
        let persistence = InMemoryPersistenceStore()
        let store = DiscoveredModelsStore(persistence: persistence)
        let id = UUID()
        store.setModels(["good"], for: id)
        store.setModels([], for: id)  // e.g. Ollama's last model was removed
        #expect(store.models(for: id) == [])  // shows "no models", NOT the stale list or curated
    }

    @Test("prune drops entries for connections no longer present")
    func prune() {
        let persistence = InMemoryPersistenceStore()
        let store = DiscoveredModelsStore(persistence: persistence)
        let keep = UUID()
        let drop = UUID()
        store.setModels(["k"], for: keep)
        store.setModels(["d"], for: drop)
        store.prune(keeping: [keep])
        #expect(store.models(for: keep) == ["k"])
        #expect(store.models(for: drop) == nil)
    }
}
