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

    // MARK: - Themes (schema 2)

    @Test("schema 2: a bad theme entry is skipped, a future-format one is kept, apps unchanged")
    func decodesThemesPerElement() async throws {
        let http = StubHTTPClient(responses: [url: .success(Self.schema2Fixture)])
        let source = RemoteCatalogSource(url: url, http: http)
        let (apps, themes) = try await source.fetchCatalogAndThemes()

        #expect(apps.map(\.appID) == ["gitmage"])
        #expect(try await source.fetchCatalog().map(\.appID) == ["gitmage"])
        #expect(themes.map(\.id) == ["glass", "future"])
        let glass = try #require(themes.first)
        #expect(glass.kind == .theme)
        #expect(glass.format == 1)
        #expect(glass.isCompatible)
        #expect(glass.files.map(\.sha256) == ["aa", "bb"])
        #expect(themes.last?.isCompatible == false)
    }

    @Test("schema 1 (no themes key) lists no themes")
    func schema1HasNoThemes() async throws {
        let json = #"{"schemaVersion":1,"apps":[]}"#.data(using: .utf8)!
        let http = StubHTTPClient(responses: [url: .success(json)])
        let (apps, themes) = try await RemoteCatalogSource(url: url, http: http).fetchCatalogAndThemes()
        #expect(apps.isEmpty)
        #expect(themes.isEmpty)
    }

    @Test("a themes value that is not an array never costs the apps")
    func malformedThemesArrayKeepsApps() async throws {
        let json = #"{"schemaVersion":2,"apps":[\#(Self.appJSON)],"themes":{"oops":1}}"#.data(using: .utf8)!
        let http = StubHTTPClient(responses: [url: .success(json)])
        let (apps, themes) = try await RemoteCatalogSource(url: url, http: http).fetchCatalogAndThemes()
        #expect(apps.map(\.appID) == ["gitmage"])
        #expect(themes.isEmpty)
    }

    @Test("apps and themes come from one GET of the catalog")
    func oneRequestPerRefresh() async throws {
        let http = CountingHTTPClient(data: Self.schema2Fixture)
        _ = try await RemoteCatalogSource(url: url, http: http).fetchCatalogAndThemes()
        #expect(http.count == 1)
    }

    static let appJSON = """
        {"appID":"gitmage","displayName":"Git Mage","icon":"wand.and.stars","description":"Git IDE",
         "version":"v0.2.0","apiVersion":1,"downloadURL":"https://example.com/gitmage.bundle.zip",
         "sha256":"abc","sourceRepo":"AhmedMElhalaby/GitMage"}
        """

    /// 1 good theme, 1 with an unknown `kind`, 1 with `format: 99`.
    static let schema2Fixture = """
        {"schemaVersion":2,"apps":[\(appJSON)],"themes":[
          {"id":"glass","kind":"theme","displayName":"macOS Glass","description":"Glass",
           "version":"1.0.0","author":"A","format":1,
           "files":[{"url":"https://example.com/glass-light.theme","sha256":"aa"},
                    {"url":"https://example.com/glass-dark.theme","sha256":"bb"}],
           "screenshots":[]},
          {"id":"bad","kind":"wallpaper","displayName":"Bad","description":"",
           "version":"1.0.0","format":1,"files":[]},
          {"id":"future","kind":"theme","displayName":"Future","description":"",
           "version":"1.0.0","format":99,"files":[]}
        ]}
        """.data(using: .utf8)!
}

/// Counts GETs (the live source must fetch the catalog once per refresh).
private final class CountingHTTPClient: HTTPClient, @unchecked Sendable {
    let data: Data
    private(set) var count = 0
    init(data: Data) { self.data = data }
    func get(_ url: URL) async throws -> Data {
        count += 1
        return data
    }
}
