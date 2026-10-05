import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ConnectionStore")
final class ConnectionStoreTests {
    let persistence = InMemoryPersistenceStore()
    let secrets = InMemorySecretStore()

    @MainActor private func makeStore() -> ConnectionStore {
        ConnectionStore(persistence: persistence, secrets: secrets)
    }

    @Test("starts empty")
    @MainActor func startsEmpty() {
        #expect(makeStore().connections.isEmpty)
    }

    @Test("adding a connection stores metadata as a document and the token in secrets")
    @MainActor func addStoresMetadataAndSecret() {
        let store = makeStore()
        let connection = store.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Work",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-abc")

        #expect(store.connections.map(\.id) == [connection.id])
        #expect(store.token(for: connection) == "sk-abc")
        // Token must NOT be in the persisted document.
        let doc = persistence.load(ConnectionsDocument.self)
        #expect(doc?.connections.count == 1)
        #expect(doc?.connections.first?.displayName == "Work")
    }

    @Test("adding a subscription connection sets authMode and stores no token")
    @MainActor func addSubscriptionConnectionIsKeyless() {
        let store = makeStore()
        let claude = ProviderPreset.preset(id: "claude")
        let connection = store.addConnection(
            preset: claude, displayName: "Claude", baseURL: claude.defaultBaseURL,
            token: "", authMode: .subscription)

        #expect(connection.authMode == .subscription)
        #expect(store.token(for: connection) == nil)  // keyless — no secret written
        // authMode round-trips through the persisted document.
        let doc = persistence.load(ConnectionsDocument.self)
        #expect(doc?.connections.first?.authMode == .subscription)
    }

    @Test("connections survive a fresh store (metadata reloads; secret stays in keychain)")
    @MainActor func survivesReload() {
        let first = makeStore()
        let connection = first.addConnection(
            preset: ProviderPreset.preset(id: "openai"), displayName: "Personal",
            baseURL: ProviderPreset.preset(id: "openai").defaultBaseURL, token: "sk-xyz")

        let second = makeStore()
        #expect(second.connections.map(\.id) == [connection.id])
        #expect(second.token(for: connection) == "sk-xyz")
    }

    @Test("removing a connection clears its metadata and secret")
    @MainActor func removeClearsBoth() {
        let store = makeStore()
        let connection = store.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "X",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "t")
        store.removeConnection(connection)

        #expect(store.connections.isEmpty)
        #expect(store.token(for: connection) == nil)
        #expect(persistence.load(ConnectionsDocument.self)?.connections.isEmpty == true)
    }
}
