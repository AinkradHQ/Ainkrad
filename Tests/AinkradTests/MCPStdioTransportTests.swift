import AinkradHostRuntime
// Tests/AinkradTests/MCPStdioTransportTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("StdioTransport (real subprocess)")
struct MCPStdioTransportTests {
    /// A `cat`-based echo server: newline-delimited JSON in → same line out.
    /// Verifies real spawn + framing without a heavyweight MCP binary.
    @Test func echoesNewlineDelimitedJSON() async throws {
        let t = StdioTransport(command: "/bin/cat", args: [], env: [:])
        try await t.start()
        defer { Task { await t.stop() } }

        var iterator = t.incoming().makeAsyncIterator()
        try await t.send(
            .object([
                "jsonrpc": .string("2.0"), "id": .string("1"),
                "method": .string("ping"), "params": .object([:]),
            ]))
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "1")
        #expect(received?["method"]?.stringValue == "ping")
    }

    @Test func startFailsForMissingExecutable() async {
        let t = StdioTransport(command: "/nonexistent/bin/does-not-exist", args: [], env: [:])
        await #expect(throws: MCPError.self) { try await t.start() }
    }

    /// A routine failure mode: the MCP server has closed its read end of stdin
    /// (e.g. crashed reader, half-dead process) while the process itself is
    /// still alive (`isRunning == true`), so the `isRunning` guard in `send()`
    /// does not save us — the write itself must EPIPE into a typed error, not
    /// an uncaught exception that crashes the host.
    @Test func sendAfterPeerClosedStdinThrowsTypedError() async throws {
        // Closes fd 0 (stdin) immediately, then sleeps — process stays alive
        // (isRunning == true) but nothing is reading the pipe, so any write
        // from our side hits EPIPE deterministically.
        let t = StdioTransport(command: "/bin/sh", args: ["-c", "exec 0<&-; sleep 5"], env: [:])
        try await t.start()
        defer { Task { await t.stop() } }

        // Give the child a moment to actually close its stdin before we write.
        try await Task.sleep(for: .milliseconds(200))

        await #expect(throws: MCPError.self) {
            try await t.send(
                .object([
                    "jsonrpc": .string("2.0"), "id": .string("1"),
                    "method": .string("ping"), "params": .object([:]),
                ]))
        }
    }

    /// Garbage (non-JSON) lines from the subprocess must be silently dropped by
    /// `LineParser`/`JSONValue.parse`, never crash the reader, while valid JSON
    /// lines that follow still arrive intact.
    @Test func swallowsGarbageLineAndDeliversValidJSON() async throws {
        let t = StdioTransport(
            command: "/bin/sh",
            args: [
                "-c",
                "printf 'not json at all\\n{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"ping\",\"params\":{}}\\n'; sleep 1",
            ],
            env: [:]
        )
        try await t.start()
        defer { Task { await t.stop() } }

        var iterator = t.incoming().makeAsyncIterator()
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "1")
        #expect(received?["method"]?.stringValue == "ping")
    }
}
