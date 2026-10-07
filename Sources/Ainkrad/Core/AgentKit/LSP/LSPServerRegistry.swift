import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/LSP/LSPServerRegistry.swift
import Foundation

/// Connection health for one (language, workspace-root) LSP session.
enum LSPHealth: Equatable {
    case connected
    case failed(String)
}

/// Owns the live LSP connections: resolves which configured language server handles a
/// given file (by glob match against `LSPServersDocument`), lazily starts and caches ONE
/// `LSPClient` per (language, workspace-root), and tracks health.
///
/// Advisory, never blocking: a language with no enabled/configured server, or one whose
/// client fails to start, yields `nil` from `client(forFilePath:rootURI:)` — it never
/// throws. One failing server can't break another: each (language, root) is started
/// independently, so a bad "swift" config still leaves "python" working.
@MainActor
final class LSPServerRegistry {
    private var doc: LSPServersDocument
    private let persistence: PersistenceStore
    private let clientFactory: @MainActor @Sendable (LSPServerConfig) -> LSPClient?
    private var clients: [String: LSPClient] = [:]
    private(set) var health: [String: LSPHealth] = [:]

    /// - Parameter clientFactory: builds a real transport-backed client from a config.
    ///   Injectable so tests pass a stub-backed client and never spawn a real language
    ///   server process.
    init(
        persistence: PersistenceStore,
        clientFactory: @escaping @MainActor @Sendable (LSPServerConfig) -> LSPClient? =
            LSPServerRegistry.defaultClientFactory
    ) {
        self.doc = persistence.load(LSPServersDocument.self) ?? LSPServersDocument()
        self.persistence = persistence
        self.clientFactory = clientFactory
    }

    /// First-launch bootstrap: seeds `doc.servers` with `configs` (typically
    /// `autodetect()`'s result) and persists them — but ONLY when the document
    /// is currently empty. A user who has already added or edited configs (or
    /// simply has some persisted from a prior autodetect) is never clobbered;
    /// this is a no-op on every subsequent launch. See `AppEnvironment.bootstrap()`,
    /// which calls this off the launch path since `autodetect()` shells out to
    /// `which` per known server.
    func seedIfEmpty(with configs: [LSPServerConfig]) {
        guard doc.servers.isEmpty, !configs.isEmpty else { return }
        doc.servers = configs
        persistence.save(doc)
    }

    /// Disconnects every currently-connected client (best-effort `shutdown()` +
    /// transport stop) and clears cached clients/health. Mirrors
    /// `MCPServerRegistry.disconnectAll()` — for app-quit/teardown callers and
    /// for the config UI (Task 19) to cleanly restart a client after an edit.
    func disconnectAll() async {
        for client in clients.values { await client.shutdown() }
        clients.removeAll()
        health.removeAll()
    }

    /// Builds a real `LSPStdioTransport`-backed client from a config. A config with an
    /// empty command (e.g. autodetection found nothing) yields `nil` rather than
    /// attempting to spawn an empty path.
    static func defaultClientFactory(_ config: LSPServerConfig) -> LSPClient? {
        guard !config.command.isEmpty else { return nil }
        let transport = LSPStdioTransport(command: config.command, args: config.args, env: [:])
        return LSPClient(transport: transport)
    }

    /// The language id of the first enabled config whose `fileGlobs` matches `filePath`,
    /// or `nil` when nothing configured/enabled applies to this file.
    func language(forFilePath filePath: String) -> String? {
        let name = (filePath as NSString).lastPathComponent
        for config in doc.servers where config.enabled {
            if config.fileGlobs.contains(where: { Self.matches(glob: $0, name: name) }) {
                return config.id
            }
        }
        return nil
    }

    /// Lazily starts (or reuses) the one `LSPClient` for the language serving `filePath`,
    /// scoped to `rootURI` — repeated calls for the same (language, root) pair return the
    /// SAME client instance rather than spawning another server. Returns `nil` — never
    /// throws — when no server is configured/enabled for this file, its config has no
    /// resolvable command, or its handshake failed (recorded in `health`; other
    /// (language, root) pairs are unaffected).
    func client(forFilePath filePath: String, rootURI: String) async -> LSPClient? {
        guard let language = language(forFilePath: filePath) else { return nil }
        let key = cacheKey(language: language, rootURI: rootURI)
        if let existing = clients[key] { return existing }
        guard let config = doc.servers.first(where: { $0.id == language && $0.enabled }) else { return nil }
        guard let client = clientFactory(config) else {
            health[key] = .failed("no server available for '\(language)'")
            return nil
        }
        do {
            try await client.initialize(rootURI: rootURI)
            clients[key] = client
            health[key] = .connected
            return client
        } catch {
            health[key] = .failed(String(describing: error))
            return nil
        }
    }

    private func cacheKey(language: String, rootURI: String) -> String {
        "\(language)::\(rootURI)"
    }

    // MARK: - Config UI (Task 19) accessors

    /// Every configured language server, for the config UI's list. Mirrors
    /// `MCPServerConfigStore.all()`.
    func servers() -> [LSPServerConfig] { doc.servers }

    /// One configured server by language id, or `nil` if none. Mirrors
    /// `MCPServerConfigStore.config(id:)`.
    func config(id: String) -> LSPServerConfig? {
        doc.servers.first { $0.id == id }
    }

    /// Persists `config` (replacing the existing entry with the same `id`, or
    /// appending a new one) and invalidates any live client(s) for that
    /// language so the next file resolution picks up the edited
    /// command/args/globs rather than reusing a client bound to the OLD
    /// config. Mirrors `MCPServerConfigStore.upsert`, fused with the
    /// reconnect-after-edit hook the MCP servers tab uses via
    /// `MCPServerRegistry.connectEnabled()` — the LSP equivalent is narrower
    /// (just this one language's cache) since clients are lazy per file
    /// rather than eagerly connected in a batch.
    func upsert(_ config: LSPServerConfig) {
        if let i = doc.servers.firstIndex(where: { $0.id == config.id }) {
            doc.servers[i] = config
        } else {
            doc.servers.append(config)
        }
        persistence.save(doc)
        invalidateClients(forLanguage: config.id)
    }

    /// Enables/disables a configured server by language id and invalidates
    /// its live client(s) so the next lookup re-checks `enabled`. Mirrors
    /// `MCPServerConfigStore.setEnabled(_:for:)`. A no-op if `id` isn't
    /// configured.
    func setEnabled(_ value: Bool, for id: String) {
        guard let i = doc.servers.firstIndex(where: { $0.id == id }) else { return }
        doc.servers[i].enabled = value
        persistence.save(doc)
        invalidateClients(forLanguage: id)
    }

    /// Removes a configured server (LSP configs carry no secrets, unlike MCP,
    /// so there's nothing else to clean up) and invalidates its live
    /// client(s). Mirrors `MCPServerConfigStore.remove(id:)`.
    func remove(id: String) {
        doc.servers.removeAll { $0.id == id }
        persistence.save(doc)
        invalidateClients(forLanguage: id)
    }

    /// Drops every cached client/health entry for `language` (across every
    /// workspace root) so the next `client(forFilePath:rootURI:)` call opens
    /// a fresh one against the just-persisted config, scoped to this one
    /// language so editing "python" can never disrupt a live "swift" session.
    /// Best-effort `shutdown()` of the dropped client(s) is fired off in the
    /// background (mirroring `disconnectAll()`'s teardown) since this method
    /// itself is synchronous, matching `MCPServerConfigStore`'s synchronous
    /// mutators that the config UI calls directly from SwiftUI actions.
    private func invalidateClients(forLanguage language: String) {
        let prefix = "\(language)::"
        for key in clients.keys.filter({ $0.hasPrefix(prefix) }) {
            if let client = clients.removeValue(forKey: key) {
                Task { await client.shutdown() }
            }
            health.removeValue(forKey: key)
        }
    }

    /// Supports the one glob shape every built-in/autodetected config uses: a `*`-prefixed
    /// extension suffix (`*.swift`, `*.tsx`, ...). Anything else is matched as a literal
    /// file name.
    private static func matches(glob: String, name: String) -> Bool {
        if glob.hasPrefix("*") {
            return name.hasSuffix(String(glob.dropFirst()))
        }
        return glob == name
    }

    // MARK: - PATH autodetection

    private nonisolated static let knownServers: [(language: String, binary: String, globs: [String])] = [
        ("swift", "sourcekit-lsp", ["*.swift"]),
        ("typescript", "typescript-language-server", ["*.ts", "*.tsx"]),
        ("go", "gopls", ["*.go"]),
        ("python", "pyright-langserver", ["*.py"]),
        ("rust", "rust-analyzer", ["*.rs"]),
    ]

    /// Probes PATH for each known language server binary, returning an enabled
    /// `LSPServerConfig` for every one found.
    ///
    /// - Parameter which: resolves a binary name to its absolute path on PATH, or `nil`
    ///   if not found. Defaults to a real `/usr/bin/which` lookup, but tests MUST inject a
    ///   fake resolver — this must never spawn a real process or depend on what happens
    ///   to be installed on the machine running the tests.
    nonisolated static func autodetect(which: (String) -> String? = defaultWhich) -> [LSPServerConfig] {
        knownServers.compactMap { entry in
            guard let resolved = which(entry.binary) else { return nil }
            return LSPServerConfig(
                id: entry.language, command: resolved, args: [],
                fileGlobs: entry.globs, enabled: true)
        }
    }

    /// Real PATH lookup via `/usr/bin/which <binary>` — mirrors `DittoUnzipper.entryNames`'s
    /// Process+Pipe pattern. Returns the resolved absolute path, or `nil` if not found or
    /// the lookup itself failed to launch/exit cleanly.
    nonisolated static func defaultWhich(_ binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
