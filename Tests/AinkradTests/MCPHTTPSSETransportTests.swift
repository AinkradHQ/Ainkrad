import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("HTTPSSETransport")
struct MCPHTTPSSETransportTests {
    /// `StreamingHTTPClient` stub that replays canned response bytes and
    /// records requests — no real network involved.
    private final class StubHTTP: StreamingHTTPClient, @unchecked Sendable {
        let chunks: [String]
        private(set) var requests: [URLRequest] = []
        init(chunks: [String]) { self.chunks = chunks }
        func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
            requests.append(request)
            let data = chunks.map { Data($0.utf8) }
            return AsyncThrowingStream { cont in
                for c in data { cont.yield(c) }
                cont.finish()
            }
        }
    }

    /// Stub that always fails at the HTTP layer, mirroring how the real
    /// `URLSessionStreamingHTTPClient` surfaces non-2xx responses.
    private struct FailingHTTP: StreamingHTTPClient {
        func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
            throw StreamingHTTPError.status(500, body: "server exploded")
        }
    }

    private func ping(id: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": .string(id),
            "method": .string("ping"), "params": .object([:]),
        ])
    }

    @Test func rejectsNonHTTPSEndpoint() async {
        let t = HTTPSSETransport(
            endpoint: URL(string: "http://mcp.example/api")!,
            authHeaders: [:], http: StubHTTP(chunks: []))
        await #expect(throws: MCPError.self) { try await t.start() }
    }

    @Test func yieldsSSEEventsAsJSONMessages() async throws {
        let stub = StubHTTP(chunks: ["data: {\"jsonrpc\":\"2.0\",\"id\":\"1\",\"result\":{}}\n", "\n"])
        let t = HTTPSSETransport(
            endpoint: URL(string: "https://mcp.example/api")!,
            authHeaders: ["Authorization": "Bearer tok"], http: stub)
        try await t.start()
        var iterator = t.incoming().makeAsyncIterator()
        try await t.send(ping(id: "1"))
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "1")
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func yieldsPlainJSONBodyWhenNotSSE() async throws {
        let stub = StubHTTP(chunks: ["{\"jsonrpc\":\"2.0\",\"id\":\"2\",\"result\":{\"ok\":true}}\n"])
        let t = HTTPSSETransport(
            endpoint: URL(string: "https://mcp.example/api")!,
            authHeaders: [:], http: stub)
        try await t.start()
        var iterator = t.incoming().makeAsyncIterator()
        try await t.send(ping(id: "2"))
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "2")
    }

    @Test func httpErrorStatusMapsToTypedTransportError() async throws {
        let t = HTTPSSETransport(
            endpoint: URL(string: "https://mcp.example/api")!,
            authHeaders: [:], http: FailingHTTP())
        try await t.start()
        await #expect(throws: MCPError.self) {
            try await t.send(ping(id: "x"))
        }
    }

    @Test func malformedSSEPayloadIsSkippedNotCrashing() async throws {
        let stub = StubHTTP(chunks: [
            "data: not-valid-json-at-all\n", "\n",
            "data: {\"jsonrpc\":\"2.0\",\"id\":\"3\",\"result\":{}}\n", "\n",
        ])
        let t = HTTPSSETransport(
            endpoint: URL(string: "https://mcp.example/api")!,
            authHeaders: [:], http: stub)
        try await t.start()
        var iterator = t.incoming().makeAsyncIterator()
        try await t.send(ping(id: "3"))
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "3")
    }

    @Test func customAuthHeaderPassesThrough() async throws {
        let stub = StubHTTP(chunks: ["data: {\"jsonrpc\":\"2.0\",\"id\":\"4\",\"result\":{}}\n", "\n"])
        let t = HTTPSSETransport(
            endpoint: URL(string: "https://mcp.example/api")!,
            authHeaders: ["X-API-Key": "secret-value"], http: stub)
        try await t.start()
        try await t.send(ping(id: "4"))
        #expect(stub.requests.first?.value(forHTTPHeaderField: "X-API-Key") == "secret-value")
    }
}
