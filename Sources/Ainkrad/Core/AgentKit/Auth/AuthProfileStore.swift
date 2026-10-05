import AinkradHostRuntime
import Foundation

/// Non-secret metadata for multi-key auth profiles: the ORDERED list of Keychain-alias
/// labels registered per connection id. The actual key VALUES never live here — they are
/// stored in `SecretStore` (Keychain in production) under
/// `"connection.<id>.key.<alias>"`, reusing the same seam `Connection.secretID` already
/// uses for the single-key case. This document only remembers which aliases exist and in
/// what order, so it is safe to sync/export/log without leaking credentials.
struct AuthProfilesDocument: PersistableDocument {
    static let documentID = "auth-profiles"
    var aliasesByConnection: [String: [String]] = [:]

    init(aliasesByConnection: [String: [String]] = [:]) {
        self.aliasesByConnection = aliasesByConnection
    }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults) so a payload
    // missing newer keys never throws. See RouterOutcomeDocument / UsageLedgerDocument.
    private enum CodingKeys: String, CodingKey { case aliasesByConnection }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aliasesByConnection = try c.decodeIfPresent([String: [String]].self, forKey: .aliasesByConnection) ?? [:]
    }
}

/// Manages N ordered API keys per connection ("auth profiles"), rotated by
/// `FailoverController` on rate-limit/quota/auth errors.
///
/// Secrets vs. metadata split (load-bearing): key VALUES are written/read only through
/// `SecretStore` (Keychain); the persisted `AuthProfilesDocument` stores only alias labels
/// and their per-connection order. A connection with no registered aliases falls back to
/// its single primary secret at `connection.secretID`, preserving existing single-key
/// connections without migration.
@MainActor
final class AuthProfileStore {
    private var doc: AuthProfilesDocument
    private let persistence: PersistenceStore
    private let secrets: SecretStore

    init(persistence: PersistenceStore, secrets: SecretStore) {
        self.persistence = persistence
        self.secrets = secrets
        self.doc = persistence.load(AuthProfilesDocument.self) ?? AuthProfilesDocument()
    }

    /// Ordered secret VALUES for a connection: the registered aliases' Keychain values, in
    /// registration order, or — when no aliases are registered — the connection's single
    /// primary secret (if any). Aliases whose Keychain entry is missing are skipped rather
    /// than surfaced as empty strings.
    func keys(for connection: Connection) -> [String] {
        let aliases = doc.aliasesByConnection[connection.id.uuidString] ?? []
        if aliases.isEmpty {
            return secrets.secret(for: connection.secretID).map { [$0] } ?? []
        }
        return aliases.compactMap { secrets.secret(for: keychainID(connection, $0)) }
    }

    /// Registers (or overwrites) a key under `alias` for `connection`. The key VALUE goes
    /// to `SecretStore` only; the document records just the alias label, appended to the
    /// end of the order if new.
    func addKey(_ value: String, alias: String, for connection: Connection) {
        secrets.setSecret(value, for: keychainID(connection, alias))
        var aliases = doc.aliasesByConnection[connection.id.uuidString] ?? []
        if !aliases.contains(alias) { aliases.append(alias) }
        doc.aliasesByConnection[connection.id.uuidString] = aliases
        persistence.save(doc)
    }

    /// Removes both the Keychain entry and the alias label for `connection`.
    func removeKey(alias: String, for connection: Connection) {
        secrets.setSecret(nil, for: keychainID(connection, alias))
        doc.aliasesByConnection[connection.id.uuidString]?.removeAll { $0 == alias }
        persistence.save(doc)
    }

    private func keychainID(_ c: Connection, _ alias: String) -> String {
        "connection.\(c.id.uuidString).key.\(alias)"
    }
}
