import Foundation
import Testing

@testable import Ainkrad

struct RemoteCatalogSourceTests {
    private let url = URL(string: "https://example.com/catalog.json")!

    @Test("decodes full catalog entries (presentation + download) from catalog.json")
    func decodes() async throws {
        let json = """
            {"schemaVersion":1,"apps":[
              {"appID":"gitmage","displayName":"Git Mage","icon":"wand.and.stars",
               "description":"Git IDE","version":"v0.2.0","apiVersion":1,
               "downloadURL":"https://example.com/gitmage.bundle.zip","sha256":"abc",
               "sourceRepo":"AhmedMElhalaby/GitMage",
               "screenshots":["https://example.com/s1.png"],
               "links":[{"title":"Home","url":"https://example.com"}]}
            ]}
            """.data(using: .utf8)!
        let http = StubHTTPClient(responses: [url: .success(json)])
        let entries = try await RemoteCatalogSource(url: url, http: http).fetchCatalog()

        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.appID == "gitmage")
        #expect(entry.version == "v0.2.0")
        #expect(entry.downloadURL == URL(string: "https://example.com/gitmage.bundle.zip"))
        #expect(entry.sha256 == "abc")
        #expect(entry.screenshots == [URL(string: "https://example.com/s1.png")!])
        #expect(entry.links.first?.title == "Home")
    }

    @Test("propagates a fetch failure so CatalogService can fall back to cache")
    func propagatesFailure() async {
        let http = StubHTTPClient(responses: [url: .failure(HTTPError.status(404))])
        await #expect(throws: HTTPError.self) {
            try await RemoteCatalogSource(url: url, http: http).fetchCatalog()
        }
    }
}
