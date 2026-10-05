import Foundation
import Testing

@testable import Ainkrad

@Suite("ClaudeProvider tool parse", .serialized)
@MainActor
struct ClaudeToolParseTests {
    @Test func parsesToolUseBlock() async throws {
        // Wire: a tool_use block streamed as start → input_json_delta(s) → stop, then message_stop.
        let wire =
            [
                #"event: content_block_start"#,
                #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file"}}"#,
                "",
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\""}}"#,
                "",
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"/tmp/a.txt\"}"}}"#,
                "",
                #"data: {"type":"content_block_stop","index":0}"#, "",
                #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#, "",
                #"data: {"type":"message_stop"}"#, "",
            ].joined(separator: "\n") + "\n"

        StubSSEProtocol.body = wire
        StubSSEProtocol.status = 200
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSSEProtocol.self]
        let http = URLSessionStreamingHTTPClient(session: URLSession(configuration: config))
        let provider = ClaudeProvider(http: http)

        var events: [AgentEvent] = []
        for try await e in provider.send(
            messages: [AgentMessage(role: .user, text: "read it")],
            system: "s", tools: [],
            model: AgentModelConfig(model: "claude-opus-4-8", effort: "xhigh"),
            credential: .apiKey("k"))
        {
            events.append(e)
        }

        #expect(events.contains(.toolUseStart(id: "toolu_1", name: "read_file")))
        #expect(
            events.contains(
                .toolUseComplete(
                    id: "toolu_1", name: "read_file",
                    input: .object(["path": .string("/tmp/a.txt")]))))
        #expect(events.contains(.done(stopReason: "tool_use")))
    }
}

/// Shared SSE stub. Define ONCE in the test target; reused by Task 9 & 10 suites.
final class StubSSEProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: StubSSEProtocol.status,
            httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(StubSSEProtocol.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
