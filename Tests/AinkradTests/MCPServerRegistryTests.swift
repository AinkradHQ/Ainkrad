import AinkradHostRuntime
// Tests/AinkradTests/MCPServerRegistryTests.swift
import Foundation
import Testing

@testable import Ainkrad

/// Transport whose `start()` always throws — used to make a server's connect fail
/// deterministically (no dependence on timing/timeouts).
private actor FailingStartTransport: MCPTransport {
    func start() async throws { throw MCPError.transport("boom") }
    func send(_ message: JSONValue) async throws {}
    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}

@Suite("MCPServerRegistry")
@MainActor
struct MCPServerRegistryTests {
    /// The canned server behaviour, extracted so a test that needs its own
    /// transport handle can reuse it instead of duplicating the script.
    private func stubResponder() -> @Sendable (JSONValue) -> [JSONValue] {
        return { message in
            guard let id = message["id"]?.stringValue,
                let method = message["method"]?.stringValue
            else { return [] }
            switch method {
            case "initialize":
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object(["capabilities": .object([:])]),
                    ])
                ]
            case "tools/list":
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object([
                            "tools": .array([
                                .object([
                                    "name": .string("search"),
                                    "inputSchema": .object(["type": .string("object")]),
                                ])
                            ])
                        ]),
                    ])
                ]
            default:
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object([:]),
                    ])
                ]
            }
        }
    }

    private func stubClientFactory()
        -> @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore, AppServerActivator?) -> MCPClient?
    {
        let responder = stubResponder()
        return { _, _, _ in MCPClient(transport: StubMCPTransport(responder: responder)) }
    }

    private func registry() -> (MCPServerRegistry, MCPServerConfigStore) {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        return (MCPServerRegistry(configStore: configs, clientFactory: stubClientFactory()), configs)
    }

    @Test func connectsEnabledServerAndDiscoversTools() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true, trusted: false))
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .connected(toolCount: 1))
        let tools = registry.discoveredTools()
        #expect(tools.map(\.descriptor.name) == ["search"])
    }

    @Test func disabledServerContributesNoTools() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: false))
        await registry.connectEnabled()
        #expect(registry.discoveredTools().isEmpty)
        #expect(registry.health["srv"] == .disabled)
    }

    @Test func serverWithMissingSecretNeedsConfiguration() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", envKeys: ["KEY"], enabled: true))
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .needsConfiguration)
        #expect(registry.discoveredTools().isEmpty)
    }

    @Test func trustFollowsEnabledAndTrustedFlags() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true, trusted: true))
        await registry.connectEnabled()
        #expect(registry.isToolTrusted("mcp/srv/search"))
        #expect(!registry.isToolTrusted("mcp/other/x"))
        #expect(!registry.isToolTrusted("read_file"))
    }

    /// Finding 2: toggling an app/server off in Settings is the ONLY control an
    /// app row has, and it re-runs `connectEnabled()`. Before the fix the client
    /// and its tools survived, so the tools stayed advertised to the model and
    /// callable via `client(for:)`.
    @Test func disablingAServerRemovesItsLiveToolsAndClient() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true, trusted: true))
        await registry.connectEnabled()
        #expect(registry.currentTools().map(\.name) == ["mcp/srv/search"])

        configs.setEnabled(false, for: "srv")
        await registry.connectEnabled()
        #expect(registry.currentTools().isEmpty)
        #expect(registry.discoveredTools().isEmpty)
        #expect(registry.client(for: "srv") == nil)
        #expect(registry.health["srv"] == .disabled)
    }

    /// Finding 2 (delete path): a server removed from the store must not stay
    /// reachable through the registry either.
    @Test func removingAServerRemovesItsLiveToolsAndClient() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true))
        await registry.connectEnabled()
        configs.remove(id: "srv")
        await registry.connectEnabled()
        #expect(registry.discoveredTools().isEmpty)
        #expect(registry.client(for: "srv") == nil)
        #expect(registry.health["srv"] == nil)
    }

    /// Finding 5: `connectEnabled()` runs on every Settings toggle and rebuilds a
    /// client per enabled config. Without disconnecting the previous one first,
    /// each toggle leaked a client — for stdio, a live child process.
    @Test func reconnectingDisconnectsThePreviousClient() async {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        // Builds each client from a transport the test keeps a handle on, so it
        // can observe whether the superseded one was actually stopped.
        final class Box: @unchecked Sendable { var transports: [StubMCPTransport] = [] }
        let box = Box()
        let responder = stubResponder()
        let factory: @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore, AppServerActivator?) -> MCPClient? = {
            _, _, _ in
            let transport = StubMCPTransport(responder: responder)
            box.transports.append(transport)
            return MCPClient(transport: transport)
        }
        let registry = MCPServerRegistry(configStore: configs, clientFactory: factory)
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true))
        await registry.connectEnabled()
        await registry.connectEnabled()
        #expect(box.transports.count == 2)
        let firstStops = await box.transports[0].stopCount
        #expect(firstStops == 1)  // the superseded client was torn down
        #expect(registry.health["srv"] == .connected(toolCount: 1))
    }

    @Test func oneFailingServerDoesNotBreakOthers() async {
        // "bad" gets a client whose transport always fails to start; "good" gets the
        // normal working stub. Deterministic (no reliance on the factory returning nil
        // or on timing): proves one server's connect failure can't stop another from
        // succeeding.
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        let workingFactory = stubClientFactory()
        let factory: @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore, AppServerActivator?) -> MCPClient? = {
            config, store, activator in
            if config.id == "bad" {
                return MCPClient(transport: FailingStartTransport())
            }
            return workingFactory(config, store, activator)
        }
        let registry = MCPServerRegistry(configStore: configs, clientFactory: factory)
        configs.upsert(
            MCPServerConfig(
                id: "bad", displayName: "Bad", transport: .stdio,
                command: "x", enabled: true))
        configs.upsert(
            MCPServerConfig(
                id: "good", displayName: "Good", transport: .stdio,
                command: "x", enabled: true))
        await registry.connectEnabled()
        if case .failed = registry.health["bad"] {
            // expected: a server whose transport fails to start surfaces as failed
        } else {
            Issue.record("expected 'bad' server to be marked failed, got \(String(describing: registry.health["bad"]))")
        }
        #expect(registry.health["good"] == .connected(toolCount: 1))
        #expect(registry.discoveredTools().map(\.descriptor.name) == ["search"])
    }

    @Test("(e) a server id containing '/' cannot borrow another server's trust")
    func slashInServerIdCannotBorrowTrust() async {
        // "web" is trusted; "web/evil" is a DIFFERENT, untrusted server that happens to
        // register a tool named "search" too, so its namespaced name
        // ("mcp/web/evil/search") collides with what a naive
        // `split(separator: "/", maxSplits: 2)` re-parse of "web"'s namespace would
        // produce. The fix must resolve ownership via the registry's actual known
        // (server, tool) pairs, not a re-derived split, so "web/evil"'s tool must NOT
        // inherit "web"'s trust.
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "web", displayName: "Web", transport: .stdio,
                command: "x", enabled: true, trusted: true))
        configs.upsert(
            MCPServerConfig(
                id: "web/evil", displayName: "Evil", transport: .stdio,
                command: "x", enabled: true, trusted: false))
        await registry.connectEnabled()

        #expect(registry.isToolTrusted("mcp/web/search"))
        #expect(!registry.isToolTrusted("mcp/web/evil/search"))
    }

    // MARK: - Discovered resources

    /// Like `stubClientFactory()`, but each server answers `resources/list`
    /// with one resource whose URI is derived from its own id — so a
    /// per-server filter that silently returned everything would fail.
    private func resourcePublishingFactory()
        -> @MainActor @Sendable (MCPServerConfig, MCPServerConfigStore, AppServerActivator?) -> MCPClient?
    {
        let base = stubResponder()
        return { config, _, _ in
            let serverID = config.id
            let responder: @Sendable (JSONValue) -> [JSONValue] = { message in
                guard let id = message["id"]?.stringValue,
                    message["method"]?.stringValue == "resources/list"
                else { return base(message) }
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object([
                            "resources": .array([
                                .object([
                                    "uri": .string("\(serverID)://buffer"),
                                    "name": .string("\(serverID) buffer"),
                                ])
                            ])
                        ]),
                    ])
                ]
            }
            return MCPClient(transport: StubMCPTransport(responder: responder))
        }
    }

    @Test("discoveredResources returns what was fetched, filtered per server")
    func discoveredResourcesAreFilteredPerServer() async {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        let registry = MCPServerRegistry(
            configStore: configs,
            clientFactory: resourcePublishingFactory())
        configs.upsert(
            MCPServerConfig(
                id: "alpha", displayName: "A", transport: .stdio,
                command: "x", enabled: true))
        configs.upsert(
            MCPServerConfig(
                id: "beta", displayName: "B", transport: .stdio,
                command: "x", enabled: true))
        await registry.connectEnabled()

        let all = registry.discoveredResources()
        #expect(all.count == 2)
        // Sorted by (server, uri) so the system-prompt listing is stable.
        #expect(all.map(\.server) == ["alpha", "beta"])

        let alpha = all.filter { $0.server == "alpha" }
        #expect(alpha.map(\.descriptor.uri) == ["alpha://buffer"])
        #expect(alpha.map(\.descriptor.name) == ["alpha buffer"])
    }

    @Test("a disabled server's resources stop being advertised")
    func discoveredResourcesDropOnDisable() async {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        let registry = MCPServerRegistry(
            configStore: configs,
            clientFactory: resourcePublishingFactory())
        configs.upsert(
            MCPServerConfig(
                id: "alpha", displayName: "A", transport: .stdio,
                command: "x", enabled: true))
        await registry.connectEnabled()
        #expect(registry.discoveredResources().count == 1)

        configs.setEnabled(false, for: "alpha")
        await registry.connectEnabled()
        #expect(registry.discoveredResources().isEmpty)
    }

    /// A server with no resources capability answers `resources/list` with an
    /// RPC error; that must leave it healthy with an empty resource list, not
    /// downgrade the connection.
    @Test("a server without resources stays connected with an empty list")
    func serverWithoutResourcesStaysHealthy() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true))
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .connected(toolCount: 1))
        #expect(registry.discoveredResources().isEmpty)
    }

    @Test func enabledAndTrustedTogglesPersistViaConfigStore() async {
        let (registry, configs) = registry()
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: false, trusted: false))
        configs.setEnabled(true, for: "srv")
        configs.setTrusted(true, for: "srv")
        #expect(configs.config(id: "srv")?.enabled == true)
        #expect(configs.config(id: "srv")?.trusted == true)
        await registry.connectEnabled()
        #expect(registry.health["srv"] == .connected(toolCount: 1))
        #expect(registry.isToolTrusted("mcp/srv/search"))
        _ = registry
    }
}
