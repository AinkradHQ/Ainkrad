import AinkradHostRuntime
import Foundation
import Observation

/// Persisted config for the optional remote channel. The bearer token is NEVER
/// stored here — it lives in `SecretStore`. Off by default.
struct RemoteChannelSettings: PersistableDocument {
    static let documentID = "remote-channel"
    var enabled: Bool = false
    var port: UInt16 = 8787
    var channelScheduleID: UUID?

    init(enabled: Bool = false, port: UInt16 = 8787, channelScheduleID: UUID? = nil) {
        self.enabled = enabled
        self.port = port
        self.channelScheduleID = channelScheduleID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? 8787
        channelScheduleID = try c.decodeIfPresent(UUID.self, forKey: .channelScheduleID)
    }
}

@MainActor
@Observable
final class RemoteChannelSettingsStore {
    static let tokenSecretID = "remote-channel.token"

    private(set) var settings: RemoteChannelSettings
    private let persistence: PersistenceStore
    private let secrets: SecretStore

    init(persistence: PersistenceStore, secrets: SecretStore) {
        self.persistence = persistence
        self.secrets = secrets
        self.settings = persistence.load(RemoteChannelSettings.self) ?? RemoteChannelSettings()
    }

    var token: String? { secrets.secret(for: Self.tokenSecretID) }

    func setEnabled(_ on: Bool) {
        settings.enabled = on
        save()
    }
    func setPort(_ port: UInt16) {
        settings.port = port
        save()
    }
    func setChannelSchedule(_ id: UUID?) {
        settings.channelScheduleID = id
        save()
    }

    @discardableResult
    func rotateToken() -> String {
        let token = (0..<32).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! }
            .reduce(into: "") { $0.append($1) }
        secrets.setSecret(token, for: Self.tokenSecretID)
        return token
    }

    func clearToken() { secrets.setSecret(nil, for: Self.tokenSecretID) }

    private func save() { persistence.save(settings) }
}
