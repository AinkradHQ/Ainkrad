import AinkradHostRuntime
// Tests/AinkradTests/MCPClientTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("MCPClient", .timeLimit(.minutes(1)))
struct MCPClientTests {
    /// Builds a stub that answers initialize/tools-list/tools-call by id.
    private func stub(
        initializeFails: Bool = false
    ) -> StubMCPTransport {
        StubMCPTransport { message in
            guard let id = message["id"]?.stringValue,
                let method = message["method"]?.stringValue
            else { return [] }
            switch method {
            case "initialize":
                if initializeFails {
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "error": .object(["code": .number(-32000), "message": .string("bad handshake")]),
                        ])
                    ]
                }
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object([
                            "capabilities": .object(["tools": .object([:])]),
                            "serverInfo": .object(["name": .string("stub")]),
                        ]),
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
                                    "description": .string("web search"),
                                    "inputSchema": .object(["type": .string("object")]),
                                ])
                            ])
                        ]),
                    ])
                ]
            case "tools/call":
                // Only "search" is a known tool; anything else is an RPC error,
                // so callTool surfaces it (drives `surfacesRPCErrors`).
                guard message["params"]?["name"]?.stringValue == "search" else {
                    return [
                        .object([
                            "jsonrpc": .string("2.0"), "id": .string(id),
                            "error": .object([
                                "code": .number(-32602),
                                "message": .string("unknown tool"),
                            ]),
                        ])
                    ]
                }
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object([
                            "content": .array([
                                .object(["type": .string("text"), "text": .string("result-text")])
                            ])
                        ]),
                    ])
                ]
            default:
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "error": .object(["code": .number(-32601), "message": .string("nope")]),
                    ])
                ]
            }
        }
    }

    @Test func connectsAndListsTools() async throws {
        let client = MCPClient(transport: stub())
        try await client.connect()
        let tools = try await client.listTools()
        #expect(tools.map(\.name) == ["search"])
    }

    @Test func connectCachesServerCapabilities() async throws {
        let client = MCPClient(transport: stub())
        try await client.connect()
        let caps = await client.serverCapabilities
        #expect(caps["tools"] != nil)
        let connected = await client.isConnected
        #expect(connected)
    }

    @Test func callsToolAndFlattensContent() async throws {
        let client = MCPClient(transport: stub())
        try await client.connect()
        let text = try await client.callTool(name: "search", arguments: .object(["q": .string("x")]))
        #expect(text == "result-text")
    }

    @Test func surfacesRPCErrors() async throws {
        let client = MCPClient(transport: stub())
        try await client.connect()
        await #expect(throws: MCPError.self) {
            _ = try await client.callTool(name: "unknown/method-triggers-default", arguments: .object([:]))
        }
    }

    @Test func handshakeErrorSurfacesTypedErrorWithoutCrashing() async throws {
        let client = MCPClient(transport: stub(initializeFails: true))
        await #expect(throws: MCPError.self) {
            try await client.connect()
        }
        let connected = await client.isConnected
        #expect(!connected)
    }

    @Test func unknownIdResponseIsIgnoredAndDoesNotHangRealWaiter() async throws {
        let transport = stub()
        let client = MCPClient(transport: transport)
        try await client.connect()

        // Inject a response for an id nobody is waiting on — must be dropped,
        // never crash, and never block the next legitimate correlation.
        await transport.inject(
            .object([
                "jsonrpc": .string("2.0"), "id": .string("does-not-exist"),
                "result": .object(["ok": .bool(true)]),
            ]))

        let tools = try await client.listTools()
        #expect(tools.map(\.name) == ["search"])
    }

    @Test func malformedInboundMessageIsSkippedNotFatal() async throws {
        let transport = stub()
        let client = MCPClient(transport: transport)
        try await client.connect()

        // No "id" and no "method" — neither a response nor a notification.
        await transport.inject(.object(["garbage": .bool(true)]))

        let text = try await client.callTool(name: "search", arguments: .object([:]))
        #expect(text == "result-text")
    }

    @Test func disconnectFailsPendingRequestsInsteadOfHanging() async throws {
        // Answers the handshake so `connect()` succeeds, then stays silent for
        // `tools/call`, so that call would await forever unless `disconnect()`
        // resolves its pending continuation.
        let silent = StubMCPTransport { message in
            guard let id = message["id"]?.stringValue else { return [] }
            if message["method"]?.stringValue == "initialize" {
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .object(["capabilities": .object([:])]),
                    ])
                ]
            }
            return []
        }
        let client = MCPClient(transport: silent)
        try await client.connect()

        let callTask = Task { try await client.callTool(name: "search", arguments: .object([:])) }
        // Give the request a moment to register itself as pending.
        try await Task.sleep(nanoseconds: 20_000_000)
        await client.disconnect()

        var threw = false
        do { _ = try await callTask.value } catch is MCPError { threw = true }
        #expect(threw)
    }

    @Test func failedHandshakeStopsTransportSoNoProcessLeaks() async throws {
        // A rejected initialize must tear the transport down — for the real
        // StdioTransport, stop() is the only path that kills the child process.
        let transport = stub(initializeFails: true)
        let client = MCPClient(transport: transport)
        await #expect(throws: MCPError.self) { try await client.connect() }
        let stopped = await transport.stopCount
        #expect(stopped == 1)
    }

    @Test func reconnectIsBoundedAndDoesNotLoopForever() async throws {
        let flaky = FlakyTransport()
        let client = MCPClient(transport: flaky)

        await #expect(throws: MCPError.self) {
            try await client.reconnect(maxAttempts: 3)
        }
        let attempts = await flaky.startAttempts
        #expect(attempts == 3)
        let connected = await client.isConnected
        #expect(!connected)
    }
}

/// Transport whose `start()` always fails — used only to prove `reconnect`
/// is bounded (never a real process/network).
private actor FlakyTransport: MCPTransport {
    private(set) var startAttempts = 0

    func start() async throws {
        startAttempts += 1
        throw MCPError.transport("always fails")
    }

    func send(_ message: JSONValue) async throws {}

    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func stop() async {}
}
