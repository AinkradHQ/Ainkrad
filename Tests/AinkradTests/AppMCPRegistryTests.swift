import AinkradAppKit
import Foundation
// Tests/AinkradTests/AppMCPRegistryTests.swift
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("MCPServerRegistry in-process")
struct AppMCPRegistryTests {
    func store() -> MCPServerConfigStore {
        MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
    }

    func activator() -> AppServerActivator {
        let server = MCPAppServer(appID: "demo")
        server.addTool(
            .init(
                name: "ping", description: "Ping.",
                schemaJSON: #"{"type":"object"}"#, readOnly: true
            ) { _ in
                AgentActionResult(text: "pong", isError: false)
            })
        return AppServerActivator(
            servers: ["demo": server], isAppOpen: { _ in true },
            requestOpen: { _ in }, availability: { _ in .available })
    }

    @Test(
        "an enabled in-process server connects and reports its tools",
        .timeLimit(.minutes(1)))
    func connectsInProcessServer() async throws {
        let configStore = store()
        configStore.upsert(
            MCPServerConfig(
                id: "demo", displayName: "Demo", transport: .inProcess,
                enabled: true, trusted: false, appID: "demo"))
        let registry = MCPServerRegistry(configStore: configStore, activator: activator())
        await registry.connectEnabled()
        #expect(registry.health["demo"] == .connected(toolCount: 1))
        #expect(registry.currentTools().map(\.name) == ["mcp/demo/ping"])
    }

    @Test(
        "an in-process config with no appID fails rather than crashing",
        .timeLimit(.minutes(1)))
    func missingAppIDFails() async {
        let configStore = store()
        configStore.upsert(
            MCPServerConfig(
                id: "broken", displayName: "Broken", transport: .inProcess,
                enabled: true, trusted: false, appID: nil))
        let registry = MCPServerRegistry(configStore: configStore, activator: activator())
        await registry.connectEnabled()
        #expect(registry.health["broken"] == .failed("invalid configuration"))
    }

    @Test(
        "a failing app server does not stop an external server connecting",
        .timeLimit(.minutes(1)))
    func failureIsIsolated() async {
        let configStore = store()
        configStore.upsert(
            MCPServerConfig(
                id: "broken", displayName: "Broken", transport: .inProcess,
                enabled: true, trusted: false, appID: nil))
        configStore.upsert(
            MCPServerConfig(
                id: "demo", displayName: "Demo", transport: .inProcess,
                enabled: true, trusted: false, appID: "demo"))
        let registry = MCPServerRegistry(configStore: configStore, activator: activator())
        await registry.connectEnabled()
        #expect(registry.health["broken"] == .failed("invalid configuration"))
        #expect(registry.health["demo"] == .connected(toolCount: 1))
    }
}
