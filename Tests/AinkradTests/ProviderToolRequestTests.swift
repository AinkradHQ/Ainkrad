import Foundation
import Testing

@testable import Ainkrad

@Suite("Provider tool request serialization", .serialized)
@MainActor
struct ProviderToolRequestTests {
    private let schema = AgentToolSchema(
        name: "read_file", description: "read a file",
        parameters: .object(["type": .string("object")]))

    @Test func claudeRequestIncludesToolsAndToolResultBlocks() async throws {
        RequestCaptureProtocol.captured = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RequestCaptureProtocol.self]
        let http = URLSessionStreamingHTTPClient(session: URLSession(configuration: config))
        let provider = ClaudeProvider(http: http)

        let messages: [AgentMessage] = [
            AgentMessage(role: .user, text: "hi"),
            AgentMessage(
                role: .assistant,
                content: [.toolUse(id: "t1", name: "read_file", input: .object(["path": .string("/x")]))]),
            AgentMessage(role: .user, content: [.toolResult(toolUseID: "t1", content: "data", isError: false)]),
        ]
        let stream = provider.send(
            messages: messages, system: "sys", tools: [schema],
            model: AgentModelConfig(model: "claude-opus-4-8", effort: "xhigh"),
            credential: .apiKey("k"))
        for try await _ in stream {}  // drives the request; capture protocol records the body

        let body = RequestCaptureProtocol.captured!
        let tools = body["tools"] as! [[String: Any]]
        #expect(tools.first?["name"] as? String == "read_file")
        let wireMessages = body["messages"] as! [[String: Any]]
        // Last message is a user tool_result content block.
        let last = wireMessages.last!
        let content = last["content"] as! [[String: Any]]
        #expect(content.first?["type"] as? String == "tool_result")
        #expect(content.first?["tool_use_id"] as? String == "t1")
    }
}

/// Captures the request body then returns an empty 200 SSE stream.
final class RequestCaptureProtocol: URLProtocol {
    nonisolated(unsafe) static var captured: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let body = request.httpBody ?? request.bodyStreamData(),
            let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        {
            RequestCaptureProtocol.captured = obj
        }
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension URLRequest {
    // URLSession moves httpBody into a stream; read it back for assertions.
    fileprivate func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: size)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
