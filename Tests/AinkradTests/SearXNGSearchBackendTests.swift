import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("SearXNGSearchBackend")
struct SearXNGSearchBackendTests {
    private final class Recorder: @unchecked Sendable { var url: URL? }

    private struct StubHTTP: DataHTTPClient {
        let json: String
        let status: Int
        let recorder: Recorder?
        init(json: String, status: Int = 200, recorder: Recorder? = nil) {
            self.json = json
            self.status = status
            self.recorder = recorder
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            recorder?.url = request.url!
            return (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    @Test func notConfiguredWhenNoURL() {
        #expect(SearXNGSearchBackend(instanceURL: "", http: StubHTTP(json: "{}")).isConfigured == false)
        #expect(SearXNGSearchBackend(instanceURL: "   ", http: StubHTTP(json: "{}")).isConfigured == false)
        #expect(SearXNGSearchBackend(instanceURL: "https://searx.example.org", http: StubHTTP(json: "{}")).isConfigured)
    }

    @Test func parsesResults() async throws {
        let json =
            #"{"results":[{"title":"T","url":"https://x","content":"D"},{"title":"T2","url":"https://y","content":"D2"}]}"#
        let backend = SearXNGSearchBackend(instanceURL: "https://searx.example.org", http: StubHTTP(json: json))
        let results = try await backend.search(query: "q", count: 5)
        #expect(
            results == [
                WebSearchResult(title: "T", url: "https://x", snippet: "D"),
                WebSearchResult(title: "T2", url: "https://y", snippet: "D2"),
            ])
    }

    @Test func honorsCount() async throws {
        let json =
            #"{"results":[{"title":"1","url":"u1","content":"c"},{"title":"2","url":"u2","content":"c"},{"title":"3","url":"u3","content":"c"}]}"#
        let backend = SearXNGSearchBackend(instanceURL: "https://searx.example.org", http: StubHTTP(json: json))
        #expect(try await backend.search(query: "q", count: 2).count == 2)
    }

    @Test func normalizesTrailingSlashAndBuildsSearchPath() async throws {
        let recorder = Recorder()
        let stub = StubHTTP(json: #"{"results":[]}"#, recorder: recorder)
        let backend = SearXNGSearchBackend(instanceURL: "https://searx.example.org///", http: stub)
        _ = try await backend.search(query: "hello world", count: 5)
        #expect(recorder.url?.absoluteString.hasPrefix("https://searx.example.org/search?") == true)
        #expect(recorder.url?.absoluteString.contains("format=json") == true)
    }

    @Test func httpErrorThrows() async {
        let backend = SearXNGSearchBackend(
            instanceURL: "https://searx.example.org", http: StubHTTP(json: "{}", status: 403))
        await #expect(throws: (any Error).self) { try await backend.search(query: "q", count: 5) }
    }
}
