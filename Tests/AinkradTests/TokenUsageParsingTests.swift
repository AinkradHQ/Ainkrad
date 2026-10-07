import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("TokenUsage")
struct TokenUsageParsingTests {
    @Test func additionAndZero() {
        let a = TokenUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 0)
        let b = TokenUsage(input: 3, output: 2, cacheRead: 0, cacheWrite: 4)
        let s = a + b
        #expect(s == TokenUsage(input: 13, output: 7, cacheRead: 1, cacheWrite: 4))
        #expect(TokenUsage.zero == TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0))
    }

    @Test func claudeUsageParse() {
        // The provider exposes a static parser for the message_delta usage JSON.
        let json = JSONValue.parse(#"{"usage":{"output_tokens":42}}"#)!
        #expect(ClaudeProvider.usageOutput(from: json) == 42)
    }

    @Test func claudeMessageStartUsageParse() {
        let json = JSONValue.parse(
            #"{"type":"message_start","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":10,"cache_creation_input_tokens":5}}}"#
        )!
        let u = ClaudeProvider.usageInput(from: json)
        #expect(u.input == 100)
        #expect(u.cacheRead == 10)
        #expect(u.cacheWrite == 5)
        #expect(u.output == 0)
    }

    @Test func openAIUsageParse() {
        let json = JSONValue.parse(#"{"usage":{"prompt_tokens":100,"completion_tokens":20}}"#)!
        let u = OpenAICompatibleProvider.usage(from: json)
        #expect(u?.input == 100)
        #expect(u?.output == 20)
    }

    @Test func openAIUsageParseCachedTokens() {
        let json = JSONValue.parse(
            #"{"usage":{"prompt_tokens":100,"completion_tokens":20,"prompt_tokens_details":{"cached_tokens":15}}}"#)!
        let u = OpenAICompatibleProvider.usage(from: json)
        #expect(u?.cacheRead == 15)
    }

    @Test func openAIUsageParseAbsent() {
        let json = JSONValue.parse(#"{"choices":[]}"#)!
        #expect(OpenAICompatibleProvider.usage(from: json) == nil)
    }

    @Test func geminiUsageParse() {
        let json = JSONValue.parse(
            #"{"usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":30,"cachedContentTokenCount":5}}"#)!
        let u = GeminiProvider.usage(from: json)
        #expect(u?.input == 50)
        #expect(u?.output == 30)
        #expect(u?.cacheRead == 5)
    }

    /// Regression: Gemini's streaming `usageMetadata` is cumulative-so-far on EVERY chunk.
    /// The provider must yield `.usage` exactly ONCE per turn carrying the FINAL cumulative
    /// totals — not sum per-chunk values (AgentSession sums `.usage` events it receives, so
    /// yielding on each chunk would double/multi-count billed tokens).
    @MainActor
    @Test func geminiMultiChunkUsageIsFinalCumulativeNotSummed() async throws {
        struct StubStreamingHTTPClient: StreamingHTTPClient {
            let chunks: [String]
            func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
                AsyncThrowingStream { cont in
                    for c in chunks { cont.yield(Data(c.utf8)) }
                    cont.finish()
                }
            }
        }
        let chunks = [
            // chunk 1: cumulative-so-far usage (prompt=10, candidates=5)
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hel\"}],\"role\":\"model\"}}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5}}\n\n",
            // chunk 2: cumulative-so-far usage (prompt=10, candidates=12) with finishReason
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"lo\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":12}}\n\n",
        ]
        let provider = GeminiProvider(
            http: StubStreamingHTTPClient(chunks: chunks),
            baseURL: "https://generativelanguage.googleapis.com/v1beta")
        var out: [AgentEvent] = []
        for try await e in provider.send(
            messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
            model: AgentModelConfig(model: "gemini-2.5-flash", effort: "xhigh"), credential: .apiKey("k"))
        { out.append(e) }

        let usageEvents: [TokenUsage] = out.compactMap {
            if case .usage(let u) = $0 { return u }
            return nil
        }
        #expect(usageEvents.count == 1)
        #expect(usageEvents.first?.input == 10)
        #expect(usageEvents.first?.output == 12)
    }

    /// Regression: a final usage-only chunk with an EMPTY `candidates` array must not be
    /// dropped by the candidates guard before usage is parsed (same trap already fixed for
    /// the OpenAI-compatible provider).
    @MainActor
    @Test func geminiEmptyCandidatesFinalUsageChunkIsNotDropped() async throws {
        struct StubStreamingHTTPClient: StreamingHTTPClient {
            let chunks: [String]
            func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
                AsyncThrowingStream { cont in
                    for c in chunks { cont.yield(Data(c.utf8)) }
                    cont.finish()
                }
            }
        }
        let chunks = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":7,\"candidatesTokenCount\":3}}\n\n",
            // final chunk: empty candidates array, usage-only
            "data: {\"candidates\":[],\"usageMetadata\":{\"promptTokenCount\":7,\"candidatesTokenCount\":9}}\n\n",
        ]
        let provider = GeminiProvider(
            http: StubStreamingHTTPClient(chunks: chunks),
            baseURL: "https://generativelanguage.googleapis.com/v1beta")
        var out: [AgentEvent] = []
        for try await e in provider.send(
            messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
            model: AgentModelConfig(model: "gemini-2.5-flash", effort: "xhigh"), credential: .apiKey("k"))
        { out.append(e) }

        let usageEvents: [TokenUsage] = out.compactMap {
            if case .usage(let u) = $0 { return u }
            return nil
        }
        #expect(usageEvents.count == 1)
        #expect(usageEvents.first?.input == 7)
        #expect(usageEvents.first?.output == 9)
    }
}
