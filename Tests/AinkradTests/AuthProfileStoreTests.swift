import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("AuthProfileStore")
@MainActor
struct AuthProfileStoreTests {
    @Test func fallsBackToPrimarySecretWhenNoAliases() {
        let secrets = InMemorySecretStore()
        let c = Connection(
            id: UUID(), presetID: "openai", kind: .openAICompatible,
            displayName: "OpenAI", baseURL: "x", createdAt: Date())
        secrets.setSecret("primary", for: c.secretID)
        let store = AuthProfileStore(persistence: InMemoryPersistenceStore(), secrets: secrets)
        #expect(store.keys(for: c) == ["primary"])
    }

    @Test func returnsAliasesInOrder() {
        let secrets = InMemorySecretStore()
        let c = Connection(
            id: UUID(), presetID: "openai", kind: .openAICompatible,
            displayName: "OpenAI", baseURL: "x", createdAt: Date())
        let store = AuthProfileStore(persistence: InMemoryPersistenceStore(), secrets: secrets)
        store.addKey("k1", alias: "a", for: c)
        store.addKey("k2", alias: "b", for: c)
        #expect(store.keys(for: c) == ["k1", "k2"])
    }

    @Test func removeKeyDropsAliasAndSecret() {
        let secrets = InMemorySecretStore()
        let c = Connection(
            id: UUID(), presetID: "openai", kind: .openAICompatible,
            displayName: "OpenAI", baseURL: "x", createdAt: Date())
        let store = AuthProfileStore(persistence: InMemoryPersistenceStore(), secrets: secrets)
        store.addKey("k1", alias: "a", for: c)
        store.addKey("k2", alias: "b", for: c)
        store.removeKey(alias: "a", for: c)
        #expect(store.keys(for: c) == ["k2"])
        #expect(secrets.secret(for: "connection.\(c.id.uuidString).key.a") == nil)
    }

    @Test func metadataRoundTripsThroughPersistenceWithoutKeyMaterial() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let c = Connection(
            id: UUID(), presetID: "openai", kind: .openAICompatible,
            displayName: "OpenAI", baseURL: "x", createdAt: Date())
        let store = AuthProfileStore(persistence: persistence, secrets: secrets)
        store.addKey("super-secret-key", alias: "a", for: c)

        // The persisted document must contain only the alias label, never the key value.
        let doc = persistence.load(AuthProfilesDocument.self)
        #expect(doc?.aliasesByConnection[c.id.uuidString] == ["a"])

        let encoded = try? PersistenceCoding.encoder.encode(doc)
        let json = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!json.contains("super-secret-key"))

        // A freshly constructed store reading the same persistence + secrets recovers the key.
        let reloaded = AuthProfileStore(persistence: persistence, secrets: secrets)
        #expect(reloaded.keys(for: c) == ["super-secret-key"])
    }

    @Test func documentDecodesForwardCompatiblyFromEmptyPayload() throws {
        let data = try #require("{}".data(using: .utf8))
        let doc = try PersistenceCoding.decoder.decode(AuthProfilesDocument.self, from: data)
        #expect(doc.aliasesByConnection.isEmpty)
    }
}
