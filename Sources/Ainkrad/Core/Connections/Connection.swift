import AinkradHostRuntime
import Foundation

/// How a connection authenticates. `apiKey` uses the Keychain token at `secretID`;
/// `subscription` uses an OAuth bearer token owned by `OAuthCredentialStore`.
enum AuthMode: String, Codable, Sendable, Hashable { case apiKey, subscription }

/// A configured provider connection — a provider *instance*. The secret (API
/// token) is NOT stored here; it lives in the Keychain under `secretID`.
/// Multiple connections of the same kind are allowed (e.g. OpenRouter + Groq).
struct Connection: Codable, Equatable, Identifiable {
    let id: UUID
    var presetID: String
    var kind: ProviderKind
    var displayName: String
    var baseURL: String
    var createdAt: Date
    var authMode: AuthMode = .apiKey

    /// Keychain id for this connection's token.
    var secretID: String { "connection.\(id.uuidString)" }

    init(
        id: UUID, presetID: String, kind: ProviderKind, displayName: String,
        baseURL: String, createdAt: Date, authMode: AuthMode = .apiKey
    ) {
        self.id = id
        self.presetID = presetID
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.createdAt = createdAt
        self.authMode = authMode
    }

    enum CodingKeys: String, CodingKey {
        case id, presetID, kind, displayName, baseURL, createdAt, provider, authMode
    }

    /// Tolerant decode: new records carry `presetID`/`kind`/`baseURL`; legacy
    /// records carry only `provider: "claude"|"openai"` and are migrated to the
    /// matching preset (keys stay under the same `secretID`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        authMode = try c.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .apiKey

        if let presetID = try c.decodeIfPresent(String.self, forKey: .presetID) {
            self.presetID = presetID
            let preset = ProviderPreset.preset(id: presetID)
            kind = try c.decodeIfPresent(ProviderKind.self, forKey: .kind) ?? preset.kind
            baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? preset.defaultBaseURL
        } else {
            // Legacy: map the old `provider` raw value to a preset.
            let legacy = (try? c.decode(String.self, forKey: .provider)) ?? "openai"
            let presetID = (legacy == "claude") ? "claude" : "openai"
            let preset = ProviderPreset.preset(id: presetID)
            self.presetID = presetID
            kind = preset.kind
            baseURL = preset.defaultBaseURL
        }
    }

    /// Explicit encode: the `provider` legacy key is decode-only, so it's never
    /// written back — new records always persist the modern shape.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(presetID, forKey: .presetID)
        try c.encode(kind, forKey: .kind)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(authMode, forKey: .authMode)
    }
}

/// Persisted, non-secret list of connections.
struct ConnectionsDocument: PersistableDocument {
    static let documentID = "connections"
    var connections: [Connection] = []
}
