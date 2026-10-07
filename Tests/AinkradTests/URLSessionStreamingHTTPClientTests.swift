import Foundation
import Testing

@testable import Ainkrad

/// Integration coverage for the *real* `URLSessionStreamingHTTPClient` — the
/// one seam the provider tests can't reach because they inject a stub that
/// already emits well-formed SSE chunks. The regression this guards: reading
/// the response with `bytes.lines` dropped the blank lines that delimit SSE
/// events, collapsing the whole stream into one undecodable blob (Thinking…
/// then silence, no reply, no error). Serialized: the URLProtocol stub shares
/// process-wide static state.
@Suite("URLSessionStreamingHTTPClient", .serialized)
struct URLSessionStreamingHTTPClientTests {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responseBody = Data()
        nonisolated(unsafe) static var statusCode = 200

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func makeClient() -> URLSessionStreamingHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionStreamingHTTPClient(session: URLSession(configuration: config))
    }

    @Test("preserves SSE blank-line event boundaries end to end")
    func preservesEventBoundaries() async throws {
        // Real OpenAI wire format: each `data:` line is followed by a blank
        // line that ends the event. If those blank lines are lost, SSEParser
        // never flushes per event and merges everything into one payload.
        let wire =
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
            + "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n"
            + "data: [DONE]\n\n"
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseBody = Data(wire.utf8)

        let client = makeClient()
        let bytes = try await client.post(URLRequest(url: URL(string: "https://example.com/v1/chat/completions")!))

        var payloads: [String] = []
        for try await payload in SSEParser.events(from: bytes) { payloads.append(payload) }

        #expect(
            payloads == [
                "{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
                "{\"choices\":[{\"delta\":{\"content\":\" world\"}}]}",
            ])
    }

    @Test("non-2xx status throws StreamingHTTPError with the response body")
    func nonSuccessThrows() async throws {
        StubURLProtocol.statusCode = 401
        StubURLProtocol.responseBody = Data("{\"error\":{\"message\":\"nope\"}}".utf8)
        let client = makeClient()
        await #expect(throws: StreamingHTTPError.self) {
            _ = try await client.post(URLRequest(url: URL(string: "https://example.com")!))
        }
    }
}
