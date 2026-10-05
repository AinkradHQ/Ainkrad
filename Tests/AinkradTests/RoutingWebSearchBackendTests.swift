import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("RoutingWebSearchBackend")
struct RoutingWebSearchBackendTests {
    /// Returns the given payload verbatim regardless of request, so each backend
    /// is distinguishable by what its HTTP client is primed to return.
    private struct StubHTTP: DataHTTPClient {
        let payload: String
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (
                Data(payload.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    private func makeRouter(persistence: PersistenceStore) -> RoutingWebSearchBackend {
        let secrets = InMemorySecretStore()
        secrets.setSecret("k", for: BraveSearchBackend.secretID)
        return RoutingWebSearchBackend(
            persistence: persistence,
            brave: BraveSearchBackend(
                secrets: secrets,
                http: StubHTTP(payload: #"{"web":{"results":[{"title":"BRAVE","url":"u","description":"d"}]}}"#)),
            duckduckgo: DuckDuckGoSearchBackend(
                http: StubHTTP(
                    payload:
                        #"<a class="result__a" href="https://ddg">DDG</a><a class="result__snippet" href="x">s</a>"#)),
            searxngHTTP: StubHTTP(payload: #"{"results":[{"title":"SEARX","url":"u","content":"c"}]}"#))
    }

    @Test func defaultsToBrave() async throws {
        let router = makeRouter(persistence: InMemoryPersistenceStore())  // no doc saved
        #expect(router.isConfigured)
        #expect(try await router.search(query: "q", count: 5).first?.title == "BRAVE")
    }

    @Test func routesToDuckDuckGo() async throws {
        let p = InMemoryPersistenceStore()
        p.save(WebSearchSettingsDocument(provider: "duckduckgo"))
        let router = makeRouter(persistence: p)
        #expect(router.isConfigured)  // DDG is always configured
        #expect(try await router.search(query: "q", count: 5).first?.title == "DDG")
    }

    @Test func routesToSearXNGWithLiveURL() async throws {
        let p = InMemoryPersistenceStore()
        // provider selected but no URL yet → not configured
        p.save(WebSearchSettingsDocument(provider: "searxng", searxngURL: ""))
        var router = makeRouter(persistence: p)
        #expect(router.isConfigured == false)
        // set the URL → now configured and routes to SearXNG, no rebuild needed
        p.save(WebSearchSettingsDocument(provider: "searxng", searxngURL: "https://searx.example.org"))
        router = makeRouter(persistence: p)
        #expect(router.isConfigured)
        #expect(try await router.search(query: "q", count: 5).first?.title == "SEARX")
    }

    @Test func providerSwitchIsLiveAcrossCalls() async throws {
        let p = InMemoryPersistenceStore()
        let router = makeRouter(persistence: p)
        p.save(WebSearchSettingsDocument(provider: "duckduckgo"))
        #expect(try await router.search(query: "q", count: 5).first?.title == "DDG")
        // same router instance, provider changed in the store between calls
        p.save(WebSearchSettingsDocument(provider: "brave"))
        #expect(try await router.search(query: "q", count: 5).first?.title == "BRAVE")
    }
}
