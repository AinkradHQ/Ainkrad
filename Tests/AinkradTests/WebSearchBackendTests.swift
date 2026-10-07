import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("WebSearchBackend")
struct WebSearchBackendTests {
    private struct StubHTTP: DataHTTPClient {
        let json: String
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    @Test func notConfiguredWhenNoKey() {
        let backend = BraveSearchBackend(secrets: InMemorySecretStore(), http: StubHTTP(json: "{}"))
        #expect(backend.isConfigured == false)
    }
    @Test func parsesResults() async throws {
        let secrets = InMemorySecretStore()
        secrets.setSecret("key", for: BraveSearchBackend.secretID)
        let json = #"{"web":{"results":[{"title":"T","url":"https://x","description":"D"}]}}"#
        let backend = BraveSearchBackend(secrets: secrets, http: StubHTTP(json: json))
        let results = try await backend.search(query: "q", count: 5)
        #expect(results == [WebSearchResult(title: "T", url: "https://x", snippet: "D")])
    }
}
