import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("DuckDuckGoSearchBackend")
struct DuckDuckGoSearchBackendTests {
    private struct StubHTTP: DataHTTPClient {
        let html: String
        let status: Int
        init(html: String, status: Int = 200) {
            self.html = html
            self.status = status
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (
                Data(html.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    /// Trimmed shape of a real DuckDuckGo HTML result list (redirect href,
    /// <b> highlight tags, entity in snippet).
    private let fixture = """
        <div class="result results_links">
          <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fswift.org%2Fdocs&rut=x">Swift <b>Docs</b></a>
          <a class="result__snippet" href="#">The official Swift documentation &amp; guides.</a>
        </div>
        <div class="result results_links">
          <a class="result__a" href="https://developer.apple.com/swift/">Apple Swift</a>
          <a class="result__snippet" href="#">Swift resources from Apple.</a>
        </div>
        """

    @Test func alwaysConfigured() {
        #expect(DuckDuckGoSearchBackend(http: StubHTTP(html: "")).isConfigured)
    }

    @Test func parsesTitlesUrlsAndSnippets() {
        let results = DuckDuckGoSearchBackend.parse(fixture)
        #expect(results.count == 2)
        // Redirect href unwrapped, <b> stripped, entity decoded.
        #expect(
            results[0]
                == WebSearchResult(
                    title: "Swift Docs",
                    url: "https://swift.org/docs",
                    snippet: "The official Swift documentation & guides."))
        // Already-absolute href passes through.
        #expect(results[1].url == "https://developer.apple.com/swift/")
        #expect(results[1].title == "Apple Swift")
    }

    @Test func emptyPageYieldsNoResultsNotError() async throws {
        let backend = DuckDuckGoSearchBackend(http: StubHTTP(html: "<html><body>nothing</body></html>"))
        #expect(try await backend.search(query: "q", count: 5).isEmpty)
    }

    @Test func searchHonorsCount() async throws {
        let backend = DuckDuckGoSearchBackend(http: StubHTTP(html: fixture))
        #expect(try await backend.search(query: "swift", count: 1).count == 1)
    }

    @Test func httpErrorThrows() async {
        let backend = DuckDuckGoSearchBackend(http: StubHTTP(html: "", status: 500))
        await #expect(throws: (any Error).self) { try await backend.search(query: "q", count: 5) }
    }
}
