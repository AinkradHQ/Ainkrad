import AinkradHostRuntime
import Foundation

/// How Ainkrad talks to a configured MCP server.
enum MCPTransportKind: String, Codable, Equatable {
    case stdio
    case httpSSE
    /// An Ainkrad app hosting its MCP server in-process. No command, URL, or
    /// secrets — the server object is reached through `AppServerActivator`.
    case inProcess
}

/// Identifies one secret (a stdio env value or an HTTP auth-header value) belonging to a
/// configured server. `keychainID` is the namespaced `SecretStore` key — the only place the
/// actual value is ever stored.
struct MCPSecretKey: Equatable {
    let serverID: String
    let key: String
    var keychainID: String { "mcp/\(serverID)/\(key)" }
}

/// One configured MCP server. Carries only secret *key names* (`envKeys`/`headerKeys`) —
/// the values live in the Keychain under `mcp/<id>/<key>` (see `MCPSecretKey`) and are
/// NEVER written to this document, the catalog JSON, or logs.
struct MCPServerConfig: Codable, Equatable, Identifiable {
    /// Server name; also the `mcp/<id>/<key>` namespace segment.
    let id: String
    var displayName: String
    var transport: MCPTransportKind
    /// stdio: the launch command the user already has on PATH. Ainkrad records config
    /// only — it never downloads or manages the binary.
    var command: String?
    var args: [String]
    /// httpSSE: the server's HTTPS endpoint.
    var url: URL?
    /// stdio: names of secret environment variables this server needs (values in Keychain).
    var envKeys: [String]
    /// httpSSE: names of secret auth headers this server needs (values in Keychain).
    var headerKeys: [String]
    var enabled: Bool
    var trusted: Bool
    /// For `.inProcess`: the owning app's id. Nil for every other transport.
    var appID: String?

    init(
        id: String, displayName: String, transport: MCPTransportKind,
        command: String? = nil, args: [String] = [], url: URL? = nil,
        envKeys: [String] = [], headerKeys: [String] = [],
        enabled: Bool = false, trusted: Bool = false, appID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.envKeys = envKeys
        self.headerKeys = headerKeys
        self.enabled = enabled
        self.trusted = trusted
        self.appID = appID
    }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults) so a payload
    // missing newer keys never throws. See AuthProfilesDocument / RouterOutcomeDocument.
    private enum CodingKeys: String, CodingKey {
        case id, displayName, transport, command, args, url, envKeys, headerKeys, enabled, trusted, appID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? id
        transport = try c.decodeIfPresent(MCPTransportKind.self, forKey: .transport) ?? .stdio
        command = try c.decodeIfPresent(String.self, forKey: .command)
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        envKeys = try c.decodeIfPresent([String].self, forKey: .envKeys) ?? []
        headerKeys = try c.decodeIfPresent([String].self, forKey: .headerKeys) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        trusted = try c.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
        appID = try c.decodeIfPresent(String.self, forKey: .appID)
    }
}

/// The `mcp-servers.json` document: every configured MCP server. Secret values never
/// appear here — see `MCPServerConfig` and `MCPSecretKey`.
struct MCPServersDocument: PersistableDocument {
    static let documentID = "mcp-servers"
    var servers: [MCPServerConfig] = []

    init(servers: [MCPServerConfig] = []) {
        self.servers = servers
    }

    private enum CodingKeys: String, CodingKey { case servers }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        servers = try c.decodeIfPresent([MCPServerConfig].self, forKey: .servers) ?? []
    }
}
