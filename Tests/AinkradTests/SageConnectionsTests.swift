import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Validates the `ConnectionStore` interaction the Sage Connections
/// settings UI performs (add / reveal / remove a provider API key). The
/// SwiftUI layer itself is verified later by screenshot (Task B10/B11).
@Suite("Sage Connections")
@MainActor
struct SageConnectionsTests {
    private func makeStore() -> ConnectionStore {
        ConnectionStore(persistence: InMemoryPersistenceStore(), secrets: InMemorySecretStore())
    }

    @Test("adding a Claude key persists a Connection and the token under its secretID")
    func addingPersistsConnectionAndSecret() {
        let store = makeStore()

        let connection = store.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude Key",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-ant-123")

        #expect(connection.kind == .claude)
        #expect(store.connections.map(\.id) == [connection.id])
        #expect(store.token(for: connection) == "sk-ant-123")
    }

    @Test("token(for:) returns the persisted token")
    func tokenForReturnsPersistedToken() {
        let store = makeStore()
        let connection = store.addConnection(
            preset: ProviderPreset.preset(id: "openai"), displayName: "OpenAI Key",
            baseURL: ProviderPreset.preset(id: "openai").defaultBaseURL, token: "sk-oai-456")

        #expect(store.token(for: connection) == "sk-oai-456")
    }

    @Test("removeConnection clears both the metadata and the secret")
    func removeClearsMetadataAndSecret() {
        let store = makeStore()
        let connection = store.addConnection(
            preset: ProviderPreset.preset(id: "claude"), displayName: "Claude Key",
            baseURL: ProviderPreset.preset(id: "claude").defaultBaseURL, token: "sk-ant-789")

        store.removeConnection(connection)

        #expect(store.connections.isEmpty)
        #expect(store.token(for: connection) == nil)
    }
}
