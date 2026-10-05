import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("ClaudeProvider")
struct ClaudeProviderTests {
    struct StubStreamingHTTPClient: StreamingHTTPClient {
        let chunks: [String]
        let captured: (@Sendable (URLRequest) -> Void)?
        func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
            captured?(request)
            return AsyncThrowingStream { cont in
                for c in chunks { cont.yield(Data(c.utf8)) }
                cont.finish()
            }
        }
    }

    private let fixture = [
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"hmm\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" world\"}}\n\n",
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n",
        "data: {\"type\":\"message_stop\"}\n\n",
    ]

    @Test("maps SSE deltas to AgentEvents in order")
    func mapsEvents() async throws {
        let provider = ClaudeProvider(http: StubStreamingHTTPClient(chunks: fixture, captured: nil))
        var out: [AgentEvent] = []
        for try await e in provider.send(
            messages: [AgentMessage(role: .user, text: "hi")],
            system: "sys", tools: [],
            model: AgentModelConfig(model: "claude-opus-4-8", effort: "xhigh"),
            credential: .apiKey("sk-x"))
        { out.append(e) }
        #expect(
            out == [
                .thinkingDelta("hmm"), .textDelta("Hello"), .textDelta(" world"), .usage(.zero),
                .done(stopReason: "end_turn"),
            ])
    }

    @Test("sends required headers and streaming body")
    func requestShape() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        let stub = StubStreamingHTTPClient(chunks: fixture, captured: { seen = $0 })
        let provider = ClaudeProvider(http: stub)
        for try await _ in provider.send(
            messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
            model: AgentModelConfig(model: "claude-opus-4-8", effort: "xhigh"),
            credential: .apiKey("sk-x"))
        {}
        let req = try #require(seen)
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-x")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body =
            try #require(req.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            as? [String: Any]
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["model"] as? String == "claude-opus-4-8")
    }

    @Test("non-2xx response maps to .failed without leaking the API key")
    func failsWithoutLeakingKey() async throws {
        struct FailingHTTPClient: StreamingHTTPClient {
            func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
                throw StreamingHTTPError.status(401, body: "{\"error\":{\"message\":\"Invalid API key\"}}")
            }
        }
        let provider = ClaudeProvider(http: FailingHTTPClient())
        var out: [AgentEvent] = []
        for try await e in provider.send(
            messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
            model: AgentModelConfig(model: "claude-opus-4-8", effort: "xhigh"),
            credential: .apiKey("sk-secret"))
        { out.append(e) }
        #expect(out.count == 1)
        if case .failed(let message) = out.first {
            #expect(!message.contains("sk-secret"))
        } else {
            Issue.record("expected .failed event")
        }
    }
}
