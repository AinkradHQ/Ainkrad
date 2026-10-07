import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MCPServerConfigStore")
@MainActor
struct MCPServerConfigStoreTests {
    private func make() -> (MCPServerConfigStore, InMemorySecretStore) {
        let secrets = InMemorySecretStore()
        return (MCPServerConfigStore(persistence: InMemoryPersistenceStore(), secrets: secrets), secrets)
    }

    private func stdioConfig() -> MCPServerConfig {
        MCPServerConfig(
            id: "web-search", displayName: "Web Search", transport: .stdio,
            command: "npx", args: ["-y", "server"], url: nil,
            envKeys: ["API_KEY"], headerKeys: [], enabled: false, trusted: false)
    }

    @Test func upsertPersistsWithoutSecretValues() {
        let (store, _) = make()
        store.upsert(stdioConfig())
        #expect(store.all().count == 1)
        #expect(store.all().first?.envKeys == ["API_KEY"])
    }

    @Test func secretsResolveFromKeychainNotJSON() {
        let (store, secrets) = make()
        store.upsert(stdioConfig())
        store.setSecret("sk-123", for: MCPSecretKey(serverID: "web-search", key: "API_KEY"))
        #expect(store.resolvedEnv(for: "web-search")["API_KEY"] == "sk-123")
        // Stored under a namespaced Keychain id, never in the document.
        #expect(secrets.secret(for: "mcp/web-search/API_KEY") == "sk-123")
    }

    @Test func reportsMissingSecrets() {
        let (store, _) = make()
        store.upsert(stdioConfig())
        #expect(store.missingSecrets(for: "web-search") == ["API_KEY"])
        store.setSecret("x", for: MCPSecretKey(serverID: "web-search", key: "API_KEY"))
        #expect(store.missingSecrets(for: "web-search").isEmpty)
    }

    @Test func enableAndTrustFlags() {
        let (store, _) = make()
        store.upsert(stdioConfig())
        store.setEnabled(true, for: "web-search")
        store.setTrusted(true, for: "web-search")
        #expect(store.all().first?.enabled == true)
        #expect(store.all().first?.trusted == true)
    }

    @Test func documentPersistsAcrossStoreInstances() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let store1 = MCPServerConfigStore(persistence: persistence, secrets: secrets)
        store1.upsert(stdioConfig())

        let store2 = MCPServerConfigStore(persistence: persistence, secrets: secrets)
        #expect(store2.all() == [stdioConfig()])
    }

    @Test func jsonDocumentContainsNoSecretValues() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let store = MCPServerConfigStore(persistence: persistence, secrets: secrets)
        store.upsert(stdioConfig())
        store.setSecret("super-secret-value", for: MCPSecretKey(serverID: "web-search", key: "API_KEY"))

        let doc = persistence.load(MCPServersDocument.self)
        let encoded = try? PersistenceCoding.encoder.encode(doc)
        let json = String(data: encoded ?? Data(), encoding: .utf8) ?? ""
        #expect(!json.contains("super-secret-value"))
        #expect(json.contains("API_KEY"))  // key name is fine, value is not
    }

    @Test func httpSSEConfigRoundTripsWithHeaderKeys() {
        let (store, secrets) = make()
        let cfg = MCPServerConfig(
            id: "docs-server", displayName: "Docs", transport: .httpSSE,
            url: URL(string: "https://example.com/mcp"),
            headerKeys: ["Authorization"])
        store.upsert(cfg)
        store.setSecret("Bearer abc", for: MCPSecretKey(serverID: "docs-server", key: "Authorization"))
        #expect(store.resolvedHeaders(for: "docs-server")["Authorization"] == "Bearer abc")
        #expect(secrets.secret(for: "mcp/docs-server/Authorization") == "Bearer abc")
    }

    @Test func removeDropsConfigAndSecrets() {
        let (store, secrets) = make()
        store.upsert(stdioConfig())
        store.setSecret("sk-123", for: MCPSecretKey(serverID: "web-search", key: "API_KEY"))
        store.remove(id: "web-search")
        #expect(store.all().isEmpty)
        #expect(secrets.secret(for: "mcp/web-search/API_KEY") == nil)
    }
}
