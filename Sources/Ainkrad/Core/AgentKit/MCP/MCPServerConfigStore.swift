import AinkradHostRuntime
import Foundation

/// Manages configured MCP servers (`mcp-servers.json`) plus their secrets.
///
/// Secrets vs. metadata split (load-bearing): `MCPServerConfig` records only secret KEY
/// NAMES (`envKeys`/`headerKeys`); the actual values are written/read only through
/// `SecretStore` (Keychain in production), namespaced `mcp/<serverID>/<key>`. The
/// persisted document is therefore safe to sync/export/log without leaking credentials.
@MainActor
final class MCPServerConfigStore {
    private var doc: MCPServersDocument
    private let persistence: PersistenceStore
    private let secrets: SecretStore

    init(persistence: PersistenceStore, secrets: SecretStore) {
        self.persistence = persistence
        self.secrets = secrets
        self.doc = persistence.load(MCPServersDocument.self) ?? MCPServersDocument()
    }

    func all() -> [MCPServerConfig] { doc.servers }

    func config(id: String) -> MCPServerConfig? {
        doc.servers.first { $0.id == id }
    }

    func upsert(_ config: MCPServerConfig) {
        if let i = doc.servers.firstIndex(where: { $0.id == config.id }) {
            doc.servers[i] = config
        } else {
            doc.servers.append(config)
        }
        persistence.save(doc)
    }

    /// Removes the config and any secrets registered under it.
    func remove(id: String) {
        if let cfg = config(id: id) {
            for key in cfg.envKeys + cfg.headerKeys {
                secrets.setSecret(nil, for: MCPSecretKey(serverID: id, key: key).keychainID)
            }
        }
        doc.servers.removeAll { $0.id == id }
        persistence.save(doc)
    }

    func setEnabled(_ value: Bool, for id: String) {
        mutate(id) { $0.enabled = value }
    }

    func setTrusted(_ value: Bool, for id: String) {
        mutate(id) { $0.trusted = value }
    }

    /// Writes (or, with `nil`, deletes) one secret value. Never touches `doc`/JSON.
    func setSecret(_ value: String?, for key: MCPSecretKey) {
        secrets.setSecret(value, for: key.keychainID)
    }

    /// Resolved stdio environment: secret env var names mapped to their Keychain values.
    /// Keys with no stored value are omitted.
    func resolvedEnv(for id: String) -> [String: String] {
        resolved(id, keys: config(id: id)?.envKeys ?? [])
    }

    /// Resolved HTTP auth headers: secret header names mapped to their Keychain values.
    /// Keys with no stored value are omitted.
    func resolvedHeaders(for id: String) -> [String: String] {
        resolved(id, keys: config(id: id)?.headerKeys ?? [])
    }

    /// Secret key names with no stored value — a server with any of these is not yet
    /// fully configured.
    func missingSecrets(for id: String) -> [String] {
        guard let cfg = config(id: id) else { return [] }
        return (cfg.envKeys + cfg.headerKeys).filter {
            secrets.secret(for: MCPSecretKey(serverID: id, key: $0).keychainID) == nil
        }
    }

    private func resolved(_ id: String, keys: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for key in keys {
            if let value = secrets.secret(for: MCPSecretKey(serverID: id, key: key).keychainID) {
                out[key] = value
            }
        }
        return out
    }

    private func mutate(_ id: String, _ change: (inout MCPServerConfig) -> Void) {
        guard let i = doc.servers.firstIndex(where: { $0.id == id }) else { return }
        change(&doc.servers[i])
        persistence.save(doc)
    }
}
