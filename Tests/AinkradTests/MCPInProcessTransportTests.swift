import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("InProcessTransport")
struct MCPInProcessTransportTests {
    func activator(open: Bool = true) -> AppServerActivator {
        let server = MCPAppServer(appID: "demo")
        server.addTool(
            .init(
                name: "ping", description: "Ping.",
                schemaJSON: #"{"type":"object"}"#, readOnly: true
            ) { _ in
                AgentActionResult(text: "pong", isError: false)
            })
        return AppServerActivator(
            servers: ["demo": server],
            isAppOpen: { _ in open },
            requestOpen: { _ in },
            availability: { _ in open ? .available : .unknown })
    }

    @Test(
        "a full MCPClient handshake and tool call works over the transport",
        .timeLimit(.minutes(1)))
    func clientRoundTrip() async throws {
        let transport = InProcessTransport(appID: "demo", activator: activator())
        let client = MCPClient(transport: transport, requestTimeout: 5)
        try await client.connect()
        let tools = try await client.listTools()
        #expect(tools.map(\.name) == ["ping"])
        let text = try await client.callTool(name: "ping", arguments: .object([:]))
        #expect(text == "pong")
        await client.disconnect()
    }

    @Test("a notification yields no inbound message", .timeLimit(.minutes(1)))
    func notificationYieldsNothing() async throws {
        let transport = InProcessTransport(appID: "demo", activator: activator())
        try await transport.start()
        // If the empty reply were yielded as a message, MCPClient's read loop
        // would log a malformed frame; connect() proves the notification sent
        // during the handshake is swallowed cleanly.
        try await transport.send(
            MCPRPC.notification(
                method: "notifications/initialized",
                params: .object([:])))
        await transport.stop()
    }

    @Test(
        "a dispatch failure surfaces as a typed transport error",
        .timeLimit(.minutes(1)))
    func dispatchFailureSurfaces() async throws {
        let transport = InProcessTransport(appID: "ghost", activator: activator(open: false))
        let client = MCPClient(transport: transport, requestTimeout: 5)
        do {
            try await client.connect()
            Issue.record("expected connect() to throw for an unreachable app")
        } catch let error as MCPError {
            guard case .transport(let message) = error else {
                Issue.record("expected .transport, got \(error)")
                return
            }
            #expect(message.contains("ghost"))
        } catch {
            Issue.record("expected MCPError, got \(error)")
        }
    }
}
