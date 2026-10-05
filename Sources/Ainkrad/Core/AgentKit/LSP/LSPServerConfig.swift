import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/LSP/LSPServerConfig.swift
import Foundation

/// One configured language server: the language it serves, the command/args to launch it
/// (found either via PATH autodetection or hand-entered by the user), and the file globs
/// it applies to. `id` is the language id (e.g. "swift", "typescript") — also the key used
/// to look up a live `LSPClient` in `LSPServerRegistry`.
struct LSPServerConfig: Codable, Equatable, Identifiable {
    let id: String
    var command: String
    var args: [String]
    var fileGlobs: [String]
    var enabled: Bool

    init(
        id: String, command: String, args: [String] = [], fileGlobs: [String] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.command = command
        self.args = args
        self.fileGlobs = fileGlobs
        self.enabled = enabled
    }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults) so a payload
    // missing newer keys never throws. See MCPServerConfig / AuthProfilesDocument.
    private enum CodingKeys: String, CodingKey {
        case id, command, args, fileGlobs, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        fileGlobs = try c.decodeIfPresent([String].self, forKey: .fileGlobs) ?? []
        // Older payloads predating this field mean "this server was already in use" —
        // default true so an upgrade never silently disables a working server.
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// The `lsp-servers.json` document: every configured language server.
struct LSPServersDocument: PersistableDocument {
    static let documentID = "lsp-servers"
    var servers: [LSPServerConfig] = []

    init(servers: [LSPServerConfig] = []) {
        self.servers = servers
    }

    private enum CodingKeys: String, CodingKey { case servers }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        servers = try c.decodeIfPresent([LSPServerConfig].self, forKey: .servers) ?? []
    }
}
