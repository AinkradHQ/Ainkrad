// Tests/AinkradTests/GeminiProviderTests.swift
import Testing
import Foundation
@testable import Ainkrad

@MainActor
@Suite("GeminiProvider")
struct GeminiProviderTests {
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

    private func run(_ chunks: [String], captured: (@Sendable (URLRequest) -> Void)? = nil) async throws -> [AgentEvent] {
        let provider = GeminiProvider(http: StubStreamingHTTPClient(chunks: chunks, captured: captured),
                                      baseURL: "https://generativelanguage.googleapis.com/v1beta")
        var out: [AgentEvent] = []
        for try await e in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
            model: AgentModelConfig(model: "gemini-2.5-flash", effort: "xhigh"), credential: .apiKey("k")) { out.append(e) }
        return out
    }

    @Test("streams text parts then done")
    func textStream() async throws {
        let out = try await run([
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hel\"}],\"role\":\"model\"}}]}\n\n",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"lo\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}]}\n\n",
        ])
        #expect(out == [.textDelta("Hel"), .textDelta("lo"), .done(stopReason: "STOP")])
    }

    @Test("functionCall part yields toolUseStart + toolUseComplete keyed by name")
    func toolCall() async throws {
        let out = try await run([
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"read_file\",\"args\":{\"path\":\"/x\"}}}],\"role\":\"model\"},\"finishReason\":\"STOP\"}]}\n\n",
        ])
        #expect(out.contains(.toolUseStart(id: "read_file", name: "read_file")))
        #expect(out.contains(.toolUseComplete(id: "read_file", name: "read_file", input: .object(["path": .string("/x")]))))
    }

    @Test("request targets streamGenerateContent with x-goog-api-key, not leaking the key in URL")
    func requestShape() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        _ = try await run(["data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}]},\"finishReason\":\"STOP\"}]}\n\n"],
                          captured: { seen = $0 })
        let req = try #require(seen)
        #expect(req.url?.absoluteString.contains("/models/gemini-2.5-flash:streamGenerateContent") == true)
        #expect(req.url?.absoluteString.contains("alt=sse") == true)
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "k")
        #expect(req.url?.absoluteString.contains("k") == false || req.url?.query?.contains("key=") == false)
    }

    @Test("error payload maps to .failed without leaking the key")
    func errorPayload() async throws {
        struct FailingHTTPClient: StreamingHTTPClient {
            func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
                throw StreamingHTTPError.status(400, body: "{\"error\":{\"message\":\"bad model\"}}")
            }
        }
        let provider = GeminiProvider(http: FailingHTTPClient(), baseURL: "https://x/v1beta")
        var out: [AgentEvent] = []
        for try await e in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "s", tools: [],
            model: AgentModelConfig(model: "gemini-2.5-flash", effort: "xhigh"), credential: .apiKey("sk-secret")) { out.append(e) }
        if case .failed(let m) = out.first { #expect(!m.contains("sk-secret")); #expect(m == "bad model") }
        else { Issue.record("expected .failed") }
    }

    @Test("invalid base URL yields .failed instead of crashing")
    func invalidBaseURLFailsInsteadOfCrashing() async throws {
        try #require(URL(string: "http://[::1/models/gemini-2.5-flash:streamGenerateContent?alt=sse") == nil)
        let provider = GeminiProvider(http: StubStreamingHTTPClient(chunks: [], captured: nil), baseURL: "http://[::1")
        var out: [AgentEvent] = []
        for try await e in provider.send(messages: [AgentMessage(role: .user, text: "hi")], system: "sys", tools: [],
                                          model: AgentModelConfig(model: "gemini-2.5-flash", effort: "xhigh"),
                                          credential: .apiKey("sk-secret")) { out.append(e) }
        #expect(out.count == 1)
        if case .failed(let message) = out.first {
            #expect(!message.contains("sk-secret"))
        } else {
            Issue.record("expected .failed event")
        }
    }
}
