// Sources/Ainkrad/Core/AgentKit/MCP/MCPServerRegistry.swift
import Foundation
import Observation

/// Connection/health state for one configured MCP server.
enum MCPHealth: Equatable {
    case connected(toolCount: Int)
    case needsConfiguration
    case failed(String)
    case disabled
}

/// Owns the live MCP connections: reads configs from `MCPServerConfigStore`, opens
/// `MCPClient` connections over the right transport for each enabled server, tracks
/// per-server enabled/trust state (delegated to the config store, the single source of
/// truth), exposes discovered tools, and tracks health/connection status.
///
/// One bad server can never break the registry: `connectEnabled()` handles each config
/// independently inside its own do/catch, so a failing connect/listTools for server A
/// only marks A `.failed` and moves on — server B still connects and is still queryable.
@MainActor
@Observable
final class MCPServerRegistry {
    /// Exposed (not `private`) so the Settings surface (the MCP servers tab) can
    /// read/mutate configs directly while still calling back into `connectEnabled()`
    /// on this same registry to reconnect after edits.
    let configStore: MCPServerConfigStore
    private let clientFactory: @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore, AppServerActivator?) -> MCPClient?
    /// Supplies the app-side MCP servers for `.inProcess` configs. Nil in tests
    /// and contexts with no app registry — an `.inProcess` config then fails
    /// closed as `.failed("invalid configuration")`, never silently succeeds.
    private let activator: AppServerActivator?
    private var clients: [String: MCPClient] = [:]
    private var tools: [String: [MCPToolDescriptor]] = [:]
    /// Discovered resources, kept only so `requiresLiveApp(appID:method:name:)`
    /// can answer for `resources/read` the same way it does for `tools/call`.
    /// Reading a resource still goes through `MCPReadResourceTool`, which asks
    /// the client directly — this is not a read cache.
    private var resources: [String: [MCPResourceDescriptor]] = [:]
    private(set) var health: [String: MCPHealth] = [:]

    /// - Parameter clientFactory: builds the right transport-backed client from a config.
    ///   Injectable so tests pass a stub-backed client and never spawn a real process or
    ///   hit the network.
    init(configStore: MCPServerConfigStore,
         activator: AppServerActivator? = nil,
         clientFactory: @escaping @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore, AppServerActivator?) -> MCPClient? =
            MCPServerRegistry.defaultClientFactory) {
        self.configStore = configStore
        self.activator = activator
        self.clientFactory = clientFactory
    }

    /// Builds a real transport-backed client from a config. A config missing the field
    /// its transport requires (no `command` for stdio, no `url` for httpSSE) yields `nil`
    /// rather than crashing — `connectEnabled()` records that as `.failed`.
    @MainActor
    static func defaultClientFactory(_ config: MCPServerConfig,
                                      _ store: MCPServerConfigStore,
                                      _ activator: AppServerActivator?) -> MCPClient? {
        switch config.transport {
        case .stdio:
            guard let command = config.command else { return nil }
            let transport = StdioTransport(command: command, args: config.args,
                                            env: store.resolvedEnv(for: config.id))
            return MCPClient(transport: transport)
        case .httpSSE:
            guard let url = config.url else { return nil }
            let transport = HTTPSSETransport(endpoint: url,
                                              authHeaders: store.resolvedHeaders(for: config.id))
            return MCPClient(transport: transport)
        case .inProcess:
            guard let appID = config.appID, let activator,
                  activator.hasServer(appID: appID) else { return nil }
            return MCPClient(transport: InProcessTransport(appID: appID, activator: activator))
        }
    }

    /// Connects every enabled server with no missing secrets and records health.
    /// Bounded/non-hanging: `MCPClient.connect()`/`listTools()` requests already carry
    /// their own timeout, so this introduces no additional unbounded await.
    /// Re-entrant by design: the MCP servers tab calls it after every enable/edit,
    /// so it must converge on the store's CURRENT state rather than only add to
    /// what is already live. Anything previously connected is released first —
    /// otherwise a disabled server's tools stayed advertised and callable until
    /// relaunch, and a re-enable leaked the old client (a child process, for
    /// stdio) on every toggle.
    func connectEnabled() async {
        let configs = configStore.all()

        // Servers deleted from the store keep no live client or tools behind.
        let known = Set(configs.map(\.id))
        for id in Set(clients.keys).union(tools.keys).subtracting(known) {
            await release(id)
            health[id] = nil
        }

        for config in configs {
            // Unconditional, and BEFORE any of the guards below: a config that
            // is now disabled, missing secrets, or no longer buildable must lose
            // its tools just as surely as one that reconnects.
            await release(config.id)
            guard config.enabled else { health[config.id] = .disabled; continue }
            guard configStore.missingSecrets(for: config.id).isEmpty else {
                health[config.id] = .needsConfiguration
                continue
            }
            guard let client = clientFactory(config, configStore, activator) else {
                health[config.id] = .failed("invalid configuration")
                continue
            }
            do {
                try await client.connect()
                let discovered = try await client.listTools()
                clients[config.id] = client
                tools[config.id] = discovered
                // `try?`: a server with no resources capability answers
                // `resources/list` with an RPC error, and that must not
                // downgrade an otherwise healthy connection to `.failed`.
                resources[config.id] = (try? await client.listResources()) ?? []
                health[config.id] = .connected(toolCount: discovered.count)
            } catch {
                health[config.id] = .failed(String(describing: error))
                await client.disconnect()
            }
        }
    }

    /// Disconnects and forgets one server's client and discovered tools. Never
    /// throws, so it cannot narrow `connectEnabled()`'s per-server isolation.
    private func release(_ id: String) async {
        tools[id] = nil
        resources[id] = nil
        guard let client = clients.removeValue(forKey: id) else { return }
        await client.disconnect()
    }

    /// Disconnects every currently-connected client.
    func disconnectAll() async {
        for client in clients.values { await client.disconnect() }
        clients.removeAll()
        tools.removeAll()
        resources.removeAll()
    }

    /// Whether the tool/resource an in-process app is about to be asked for
    /// needs that app's window on screen. Wired into `AppServerActivator`, which
    /// force-opens the app only when this says so — see its `requiresLiveApp`.
    ///
    /// Resolves appID → config → discovered descriptor, because the registry
    /// keys everything by CONFIG id while the activator only knows the app id.
    /// An unknown app, an unconnected server, or an undeclared tool all answer
    /// `false`: the host must never invent a window-open on a claim no app made.
    func requiresLiveApp(appID: String, method: String, name: String) -> Bool {
        let serverIDs = configStore.all().filter { $0.appID == appID }.map(\.id)
        switch method {
        case "tools/call":
            return serverIDs.contains { id in
                tools[id]?.contains { $0.name == name && $0.requiresLiveApp } ?? false
            }
        case "resources/read":
            return serverIDs.contains { id in
                resources[id]?.contains { $0.uri == name && $0.requiresLiveApp } ?? false
            }
        default:
            return false
        }
    }

    /// Enabled+connected servers' discovered tools, keyed by owning server.
    func discoveredTools() -> [(server: String, descriptor: MCPToolDescriptor)] {
        tools.flatMap { server, descriptors in descriptors.map { (server: server, descriptor: $0) } }
    }

    /// Enabled+connected servers' discovered resources, keyed by owning server —
    /// the resource-side mirror of `discoveredTools()`, same shape and same
    /// "only what is live right now" contract.
    ///
    /// Sorted, unlike `discoveredTools()`. Dictionary iteration order is not
    /// stable across runs, and this feeds `MCPReadResourceTool.description`,
    /// which lands in the system prompt: an unstable order would rewrite the
    /// prompt on every turn and defeat prompt caching for no visible benefit.
    func discoveredResources() -> [(server: String, descriptor: MCPResourceDescriptor)] {
        resources
            .flatMap { server, descriptors in descriptors.map { (server: server, descriptor: $0) } }
            .sorted { ($0.server, $0.descriptor.uri) < ($1.server, $1.descriptor.uri) }
    }

    func client(for server: String) -> MCPClient? {
        clients[server]
    }

    /// The live adapter set for the `AgentToolRegistry.dynamicTools` provider:
    /// one namespaced `MCPToolAdapter` per discovered tool, bound to its owning
    /// server's connected client. A tool whose server has no live client (e.g.
    /// raced with a disconnect) is skipped rather than crashing.
    func currentTools() -> [any AgentTool] {
        discoveredTools().compactMap { server, descriptor in
            guard let client = clients[server] else { return nil }
            return MCPToolAdapter(server: server, descriptor: descriptor, client: client)
        }
    }

    /// `mcp/<server>/<tool>` is trusted iff its owning server is enabled AND trusted.
    ///
    /// Deliberately NOT a naive `split(separator: "/", maxSplits: 2)` re-parse: a server
    /// id may itself contain `/` (nothing upstream forbids it), which makes the
    /// `mcp/<server>/<tool>` scheme ambiguous to split back apart — e.g. server "web"
    /// (trusted) and server "web/evil" (untrusted) both registering a tool named
    /// "search" produce "mcp/web/search" and "mcp/web/evil/search" respectively, and a
    /// naive split of the latter would parse `parts[1] == "web"`, wrongly borrowing
    /// "web"'s trust for a tool that actually belongs to "web/evil". Instead, this walks
    /// the registry's OWN known (server, tool) pairs and reconstructs each one's
    /// namespaced name the same way `MCPToolAdapter.name` does, matching by exact string
    /// equality against real, currently-discovered tools rather than re-deriving a
    /// server id via string surgery.
    func isToolTrusted(_ namespacedName: String) -> Bool {
        for (server, descriptor) in discoveredTools() where "mcp/\(server)/\(descriptor.name)" == namespacedName {
            guard let config = configStore.config(id: server) else { return false }
            return config.enabled && config.trusted
        }
        return false
    }
}
