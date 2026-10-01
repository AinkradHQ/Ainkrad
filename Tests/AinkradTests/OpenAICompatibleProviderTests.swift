import Testing
import Foundation
@testable import Ainkrad

@MainActor
@Suite("OpenAICompatibleProvider")
struct OpenAICompatibleProviderTests {
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
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
        "data: [DONE]\n\n",
    ]

    @Test("maps SSE deltas to AgentEvents in order")
    func mapsEvents() async throws {
        let provider = OpenAICompatibleProvider(http: StubStreamingHTTPClient(chunks: fixture, captured: nil), baseURL: "https://api.openai.com/v1")
        var out: [AgentEvent] = []
        for try await e in provider.send(messages: [AgentMessage(role: .user, text: "hi")],
                                         system: "sys", tools: [],
                                         model: AgentModelConfig(model: "gpt-5", effort: "xhigh"),
                                         credential: .apiKey("sk-x")) { out.append(e) }
        #expect(out == [.textDelta("Hello"), .textDelta(" world"), .done(stopReason: "stop")])
    }

    @Test("sends required headers and streaming body")
    func requestShape() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        let stub = StubStreamingHTTPClient(chunks: fixture, captured: { seen = $0 })
        let provider = OpenAICompatibleProvider(http: stub, baseURL: "https://api.openai.com/v1")
        for try await _ in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
                                         model: AgentModelConfig(model: "gpt-5", effort: "xhigh"),
                                         credential: .apiKey("sk-x")) {}
        let req = try #require(seen)
        #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "authorization") == "Bearer sk-x")
        #expect(req.value(forHTTPHeaderField: "content-type") == "application/json")
        let body = try #require(req.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } as? [String: Any]
        #expect(body?["stream"] as? Bool == true)
        #expect(body?["model"] as? String == "gpt-5")
        let messages = try #require(body?["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.first?["content"] as? String == "sys")
        #expect(messages.last?["role"] as? String == "user")
        #expect(messages.last?["content"] as? String == "hi")
    }

    @Test("non-2xx response maps to .failed without leaking the API key")
    func failsWithoutLeakingKey() async throws {
        struct FailingHTTPClient: StreamingHTTPClient {
            func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
                throw StreamingHTTPError.status(401, body: "{\"error\":{\"message\":\"Invalid API key\"}}")
            }
        }
        let provider = OpenAICompatibleProvider(http: FailingHTTPClient(), baseURL: "https://api.openai.com/v1")
        var out: [AgentEvent] = []
        for try await e in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
                                         model: AgentModelConfig(model: "gpt-5", effort: "xhigh"),
                                         credential: .apiKey("sk-secret")) { out.append(e) }
        #expect(out.count == 1)
        if case .failed(let message) = out.first {
            #expect(!message.contains("sk-secret"))
        } else {
            Issue.record("expected .failed event")
        }
    }

    @Test("custom base URL is honored")
    func customBaseURL() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        let stub = StubStreamingHTTPClient(chunks: fixture, captured: { seen = $0 })
        let provider = OpenAICompatibleProvider(http: stub, baseURL: "https://openrouter.ai/api/v1")
        for try await _ in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "s", tools: [],
            model: AgentModelConfig(model: "x", effort: "xhigh"), credential: .apiKey("k")) {}
        #expect(try #require(seen).url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
    }

    @Test("empty key sends no authorization header (Ollama)")
    func noKeyNoAuthHeader() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        let stub = StubStreamingHTTPClient(chunks: fixture, captured: { seen = $0 })
        let provider = OpenAICompatibleProvider(http: stub, baseURL: "http://localhost:11434/v1")
        for try await _ in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "s", tools: [],
            model: AgentModelConfig(model: "llama3.2", effort: "xhigh"), credential: .apiKey("")) {}
        #expect(try #require(seen).value(forHTTPHeaderField: "authorization") == nil)
    }

    @Test("invalid base URL yields .failed instead of crashing")
    func invalidBaseURLFailsInsteadOfCrashing() async throws {
        try #require(URL(string: "http://[::1/chat/completions") == nil)
        let provider = OpenAICompatibleProvider(http: StubStreamingHTTPClient(chunks: [], captured: nil), baseURL: "http://[::1")
        var out: [AgentEvent] = []
        for try await e in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
                                          model: AgentModelConfig(model: "gpt-5", effort: "xhigh"),
                                          credential: .apiKey("sk-secret")) { out.append(e) }
        #expect(out.count == 1)
        if case .failed(let message) = out.first {
            #expect(!message.contains("sk-secret"))
        } else {
            Issue.record("expected .failed event")
        }
    }
}
