import AinkradHostRuntime
import Foundation
import Observation

/// Owns the list of `Connection`s and mediates their secrets. Metadata is
/// persisted as a document; tokens go to the `SecretStore` (Keychain) only.
@MainActor
@Observable
final class ConnectionStore {
    private(set) var connections: [Connection]
    private let persistence: PersistenceStore
    private let secrets: SecretStore

    init(persistence: PersistenceStore, secrets: SecretStore) {
        self.persistence = persistence
        self.secrets = secrets
        self.connections = persistence.load(ConnectionsDocument.self)?.connections ?? []
    }

    @discardableResult
    func addConnection(
        preset: ProviderPreset, displayName: String, baseURL: String, token: String,
        authMode: AuthMode = .apiKey
    ) -> Connection {
        let connection = Connection(
            id: UUID(), presetID: preset.id, kind: preset.kind,
            displayName: displayName, baseURL: baseURL, createdAt: Date(), authMode: authMode)
        if !token.isEmpty { secrets.setSecret(token, for: connection.secretID) }
        connections.append(connection)
        persist()
        return connection
    }

    func token(for connection: Connection) -> String? {
        secrets.secret(for: connection.secretID)
    }

    func updateToken(_ token: String, for connection: Connection) {
        secrets.setSecret(token, for: connection.secretID)
    }

    /// Switches a connection between API-key and subscription auth. Persisted
    /// on the connection record itself (unlike the token, which never touches
    /// the document) so `credentialResolver` and the settings UI agree on how
    /// this connection authenticates after a relaunch.
    func setAuthMode(_ mode: AuthMode, for connection: Connection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index].authMode = mode
        persist()
    }

    func removeConnection(_ connection: Connection) {
        secrets.setSecret(nil, for: connection.secretID)
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    private func persist() {
        persistence.save(ConnectionsDocument(connections: connections))
    }
}
