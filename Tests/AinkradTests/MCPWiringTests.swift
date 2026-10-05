import AinkradHostRuntime
// Tests/AinkradTests/MCPWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

/// Task 10: proves the wiring contract AppEnvironment relies on — without touching
/// AppEnvironment itself (which spins up real subsystems) — using the same injectable
/// seams (`clientFactory`, `dynamicTools`, `mcpTrust`) bootstrap() wires together.
@Suite("MCP wiring")
@MainActor
struct MCPWiringTests {
    @Test func dynamicToolsFlowThroughTheRegistry() async {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true, trusted: true))
        let mcp = MCPServerRegistry(
            configStore: configs,
            clientFactory: { _, _, _ in
                MCPClient(
                    transport: StubMCPTransport { message in
                        guard let id = message["id"]?.stringValue,
                            let method = message["method"]?.stringValue
                        else { return [] }
                        if method == "tools/list" {
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
                        }
                        return [
                            .object([
                                "jsonrpc": .string("2.0"), "id": .string(id),
                                "result": .object(["capabilities": .object([:])]),
                            ])
                        ]
                    })
            })
        await mcp.connectEnabled()

        // Mirrors AppEnvironment.bootstrap()'s wiring: dynamicTools reads the registry's
        // current MCP adapters, and mcpTrust delegates straight to isToolTrusted.
        let registry = AgentToolRegistry(
            tools: [ReadFileTool()],
            dynamicTools: { [weak mcp] in mcp?.currentTools() ?? [] })
        let mcpTrust: (String) -> Bool = { [weak mcp] name in mcp?.isToolTrusted(name) ?? false }

        #expect(registry.tool(named: "mcp/srv/search") != nil)
        #expect(mcpTrust("mcp/srv/search"))
        #expect(mcpTrust("mcp/srv/unknown-tool") == false)
    }

    @Test func untrustedServerToolIsNotTrusted() async {
        let configs = MCPServerConfigStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        configs.upsert(
            MCPServerConfig(
                id: "srv", displayName: "S", transport: .stdio,
                command: "x", enabled: true, trusted: false))
        let mcp = MCPServerRegistry(
            configStore: configs,
            clientFactory: { _, _, _ in
                MCPClient(
                    transport: StubMCPTransport { message in
                        guard let id = message["id"]?.stringValue,
                            let method = message["method"]?.stringValue
                        else { return [] }
                        if method == "tools/list" {
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
                        }
                        return [
                            .object([
                                "jsonrpc": .string("2.0"), "id": .string(id),
                                "result": .object(["capabilities": .object([:])]),
                            ])
                        ]
                    })
            })
        await mcp.connectEnabled()

        let mcpTrust: (String) -> Bool = { [weak mcp] name in mcp?.isToolTrusted(name) ?? false }
        #expect(mcp.currentTools().contains { $0.name == "mcp/srv/search" })
        #expect(mcpTrust("mcp/srv/search") == false)
    }
}
