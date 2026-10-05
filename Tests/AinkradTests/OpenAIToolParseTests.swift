import Foundation
import Testing

@testable import Ainkrad

@Suite("OpenAIProvider tool parse", .serialized)
@MainActor
struct OpenAIToolParseTests {
    @Test func parsesToolCallDeltas() async throws {
        let wire =
            [
                #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read_file","arguments":""}}]}}]}"#,
                "",
                #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":\""}}]}}]}"#,
                "",
                #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"/tmp/a.txt\"}"}}]}}]}"#,
                "",
                #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#, "",
                "data: [DONE]", "",
            ].joined(separator: "\n") + "\n"

        StubSSEProtocol.body = wire
        StubSSEProtocol.status = 200
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSSEProtocol.self]
        let http = URLSessionStreamingHTTPClient(session: URLSession(configuration: config))
        let provider = OpenAICompatibleProvider(http: http, baseURL: "https://api.openai.com/v1")

        var events: [AgentEvent] = []
        for try await e in provider.send(
            messages: [AgentMessage(role: .user, text: "read it")],
            system: "s", tools: [],
            model: AgentModelConfig(model: "gpt-5", effort: "xhigh"),
            credential: .apiKey("k"))
        {
            events.append(e)
        }

        #expect(events.contains(.toolUseStart(id: "call_1", name: "read_file")))
        #expect(
            events.contains(
                .toolUseComplete(
                    id: "call_1", name: "read_file",
                    input: .object(["path": .string("/tmp/a.txt")]))))
        #expect(events.contains(.done(stopReason: "tool_calls")))
    }
}
