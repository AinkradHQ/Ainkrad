import AinkradHostRuntime
// Tests/AinkradTests/LSPClientTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("LSPClient", .timeLimit(.minutes(1)))
struct LSPClientTests {
    /// Builds a stub that answers `initialize`/`textDocument/formatting` by id.
    private func stub(initializeFails: Bool = false) -> StubMCPTransport {
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
                        "result": .object(["capabilities": .object(["hoverProvider": .bool(true)])]),
                    ])
                ]
            case "textDocument/formatting":
                return [
                    .object([
                        "jsonrpc": .string("2.0"), "id": .string(id),
                        "result": .array([
                            .object([
                                "range": .object([
                                    "start": .object(["line": .number(0), "character": .number(0)]),
                                    "end": .object(["line": .number(0), "character": .number(4)]),
                                ]),
                                "newText": .string("    "),
                            ])
                        ]),
                    ])
                ]
            case "shutdown":
                return [.object(["jsonrpc": .string("2.0"), "id": .string(id), "result": .null])]
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

    @Test func initializesAndCachesServerCapabilities() async throws {
        let client = LSPClient(transport: stub())
        try await client.initialize(rootURI: "file:///proj")
        let caps = await client.serverCapabilities
        #expect(caps["hoverProvider"] != nil)
        let initialized = await client.isInitialized
        #expect(initialized)
    }

    @Test func didOpenAndDidChangeSendNotificationsWithIncrementingVersion() async throws {
        let transport = stub()
        let client = LSPClient(transport: transport)
        try await client.initialize(rootURI: "file:///proj")

        try await client.didOpen(uri: "file:///proj/a.swift", languageId: "swift", text: "let x = 1")
        try await client.didChange(uri: "file:///proj/a.swift", text: "let x = 2")

        let sent = await transport.sent
        let didOpen = sent.first { $0["method"]?.stringValue == "textDocument/didOpen" }
        let didChange = sent.first { $0["method"]?.stringValue == "textDocument/didChange" }
        #expect(didOpen?["id"] == nil, "didOpen must be a notification, not a request")
        #expect(didChange?["id"] == nil, "didChange must be a notification, not a request")
        #expect(Self.numberValue(didOpen?["params"]?["textDocument"]?["version"]) == 1)
        #expect(Self.numberValue(didChange?["params"]?["textDocument"]?["version"]) == 2)
    }

    @Test func cachesPublishedDiagnosticsRoutedByURI() async throws {
        let stub = stub()
        let client = LSPClient(transport: stub)
        try await client.initialize(rootURI: "file:///proj")

        await stub.inject(
            .object([
                "jsonrpc": .string("2.0"), "method": .string("textDocument/publishDiagnostics"),
                "params": .object([
                    "uri": .string("file:///proj/a.swift"),
                    "diagnostics": .array([
                        .object([
                            "range": .object(["start": .object(["line": .number(3), "character": .number(5)])]),
                            "severity": .number(1), "message": .string("expected ';'"),
                        ])
                    ]),
                ]),
            ]))

        var diags: [LSPDiagnostic] = []
        for _ in 0..<100 {
            diags = await client.diagnostics(for: "file:///proj/a.swift")
            if !diags.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(diags.first?.message == "expected ';'")
        #expect(diags.first?.line == 3)

        // A different URI never sees this notification's diagnostics.
        let other = await client.diagnostics(for: "file:///proj/b.swift")
        #expect(other.isEmpty)
    }

    @Test func formattingRoundTripsTextEdits() async throws {
        let client = LSPClient(transport: stub())
        try await client.initialize(rootURI: "file:///proj")
        let edits = try await client.formatting(uri: "file:///proj/a.swift")
        #expect(edits.count == 1)
        #expect(edits.first?.newText == "    ")
        #expect(edits.first?.endCharacter == 4)
    }

    @Test func requestTimesOutTypedWhenServerNeverResponds() async throws {
        // Answers the handshake, then stays silent for everything else, so
        // `formatting` would await forever unless the timeout ceiling fires.
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
        let client = LSPClient(transport: silent, requestTimeout: 0.1)
        try await client.initialize(rootURI: "file:///proj")

        await #expect(throws: MCPError.self) {
            _ = try await client.formatting(uri: "file:///proj/a.swift")
        }
    }

    @Test func handshakeFailureTearsDownTransportAndSurfacesTypedError() async throws {
        let transport = stub(initializeFails: true)
        let client = LSPClient(transport: transport)
        await #expect(throws: MCPError.self) {
            try await client.initialize(rootURI: "file:///proj")
        }
        let stopped = await transport.stopCount
        #expect(stopped == 1)
        let initialized = await client.isInitialized
        #expect(!initialized)
    }

    @Test func shutdownSendsShutdownAndExitThenStopsTransport() async throws {
        let transport = stub()
        let client = LSPClient(transport: transport)
        try await client.initialize(rootURI: "file:///proj")
        await client.shutdown()

        let sent = await transport.sent
        #expect(sent.contains { $0["method"]?.stringValue == "shutdown" })
        #expect(sent.contains { $0["method"]?.stringValue == "exit" && $0["id"] == nil })
        let stopped = await transport.stopCount
        #expect(stopped == 1)
    }

    private static func numberValue(_ value: JSONValue?) -> Double? {
        if case .number(let n)? = value { return n }
        return nil
    }
}
