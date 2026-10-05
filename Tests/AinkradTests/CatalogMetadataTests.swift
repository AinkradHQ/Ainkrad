import Foundation
import Testing

@testable import Ainkrad

/// AIN-147: the app detail page's new catalog metadata — `author`,
/// `longDescription`, `screenshots`, `links` — flowing from the release
/// manifest into `CatalogEntry`. All new fields are optional on
/// `PluginManifest` so pre-existing manifests keep decoding unchanged.
struct CatalogMetadataTests {
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test("ManifestLink decodes {title,url}")
    func manifestLinkDecodes() throws {
        let link: ManifestLink = try decode(#"{"title":"Homepage","url":"https://example.com"}"#)
        #expect(link.title == "Homepage")
        #expect(link.url == URL(string: "https://example.com"))
    }

    @Test("PluginManifest decodes the new optional fields when present")
    func manifestWithNewFields() throws {
        let json = """
            {"id":"hello","name":"Hello","icon":"hand.wave","description":"Hi","apiVersion":1,"sha256":"abc123",
             "author":"Ahmed M. Elhalaby","longDescription":"A much longer description of Hello.",
             "screenshots":["https://example.com/1.png","https://example.com/2.png"],
             "links":[{"title":"Homepage","url":"https://example.com"}]}
            """
        let manifest: PluginManifest = try decode(json)
        #expect(manifest.author == "Ahmed M. Elhalaby")
        #expect(manifest.longDescription == "A much longer description of Hello.")
        #expect(
            manifest.screenshots == [
                URL(string: "https://example.com/1.png")!, URL(string: "https://example.com/2.png")!,
            ])
        #expect(manifest.links == [ManifestLink(title: "Homepage", url: URL(string: "https://example.com")!)])
    }

    @Test("PluginManifest decodes a legacy manifest missing the new fields — all nil (backward-compat)")
    func manifestLegacy() throws {
        let json =
            #"{"id":"hello","name":"Hello","icon":"hand.wave","description":"Hi","apiVersion":1,"sha256":"abc123"}"#
        let manifest: PluginManifest = try decode(json)
        #expect(manifest.author == nil)
        #expect(manifest.longDescription == nil)
        #expect(manifest.screenshots == nil)
        #expect(manifest.links == nil)
    }

    @Test("CatalogEntry defaults screenshots/links to [] and author/longDescription to nil when omitted")
    func catalogEntryDefaults() {
        let entry = CatalogEntry(
            appID: "hello", displayName: "Hello", icon: "hand.wave", description: "Hi",
            version: "1.0.0", apiVersion: 1, downloadURL: URL(string: "https://e/hello.zip")!,
            sha256: "abc123", sourceRepo: "acme/hello")
        #expect(entry.author == nil)
        #expect(entry.longDescription == nil)
        #expect(entry.screenshots == [])
        #expect(entry.links == [])
    }

    @Test("CatalogEntry carries the new fields when supplied")
    func catalogEntryWithFields() {
        let link = ManifestLink(title: "Homepage", url: URL(string: "https://example.com")!)
        let entry = CatalogEntry(
            appID: "hello", displayName: "Hello", icon: "hand.wave", description: "Hi",
            version: "1.0.0", apiVersion: 1, downloadURL: URL(string: "https://e/hello.zip")!,
            sha256: "abc123", sourceRepo: "acme/hello", author: "Ahmed M. Elhalaby",
            longDescription: "Longer text", screenshots: [URL(string: "https://example.com/1.png")!], links: [link])
        #expect(entry.author == "Ahmed M. Elhalaby")
        #expect(entry.longDescription == "Longer text")
        #expect(entry.screenshots == [URL(string: "https://example.com/1.png")!])
        #expect(entry.links == [link])
    }

    @Test("CatalogEntry round-trips through Codable (persisted cache) including the new fields")
    func catalogEntryCodableRoundTrip() throws {
        let link = ManifestLink(title: "Homepage", url: URL(string: "https://example.com")!)
        let entry = CatalogEntry(
            appID: "hello", displayName: "Hello", icon: "hand.wave", description: "Hi",
            version: "1.0.0", apiVersion: 1, downloadURL: URL(string: "https://e/hello.zip")!,
            sha256: "abc123", sourceRepo: "acme/hello", author: "Ahmed M. Elhalaby",
            longDescription: "Longer text", screenshots: [URL(string: "https://example.com/1.png")!], links: [link])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CatalogEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test("CatalogEntry decodes a legacy cached JSON without the new fields (persisted-cache backward-compat)")
    func catalogEntryLegacyCacheDecode() throws {
        let json = """
            {"appID":"hello","displayName":"Hello","icon":"hand.wave","description":"Hi","version":"1.0.0",
             "apiVersion":1,"downloadURL":"https://e/hello.zip","sha256":"abc123","sourceRepo":"acme/hello"}
            """
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
        #expect(entry.author == nil)
        #expect(entry.longDescription == nil)
        #expect(entry.screenshots == [])
        #expect(entry.links == [])
    }

    @Test("GitHubReleasesCatalogSource maps the new manifest fields into the CatalogEntry")
    func mapsNewFieldsFromManifest() async throws {
        let rel = URL(string: "https://api.github.com/repos/acme/hello/releases/latest")!
        let man = URL(string: "https://example.com/ainkrad-plugin.json")!
        let zip = URL(string: "https://example.com/Hello.bundle.zip")!
        let releaseJSON = """
            {"tag_name":"1.2.0","assets":[
              {"name":"ainkrad-plugin.json","browser_download_url":"\(man.absoluteString)"},
              {"name":"Hello.bundle.zip","browser_download_url":"\(zip.absoluteString)"}]}
            """.data(using: .utf8)!
        let manifestJSON = """
            {"id":"hello","name":"Hello","icon":"hand.wave","description":"Hi","apiVersion":1,"sha256":"abc123",
             "author":"Ahmed M. Elhalaby","longDescription":"A longer story about Hello.",
             "screenshots":["https://example.com/1.png"],
             "links":[{"title":"Homepage","url":"https://example.com"}]}
            """.data(using: .utf8)!
        let http = StubHTTPClient(responses: [rel: .success(releaseJSON), man: .success(manifestJSON)])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/hello"], http: http)
        let entries = try await source.fetchCatalog()
        #expect(entries.first?.author == "Ahmed M. Elhalaby")
        #expect(entries.first?.longDescription == "A longer story about Hello.")
        #expect(entries.first?.screenshots == [URL(string: "https://example.com/1.png")!])
        #expect(entries.first?.links == [ManifestLink(title: "Homepage", url: URL(string: "https://example.com")!)])
    }

    @Test("GitHubReleasesCatalogSource defaults screenshots/links to [] when the manifest omits them")
    func mapsDefaultsFromLegacyManifest() async throws {
        let rel = URL(string: "https://api.github.com/repos/acme/legacy/releases/latest")!
        let man = URL(string: "https://example.com/legacy-ainkrad-plugin.json")!
        let zip = URL(string: "https://example.com/Legacy.bundle.zip")!
        let releaseJSON = """
            {"tag_name":"1.0.0","assets":[
              {"name":"ainkrad-plugin.json","browser_download_url":"\(man.absoluteString)"},
              {"name":"Legacy.bundle.zip","browser_download_url":"\(zip.absoluteString)"}]}
            """.data(using: .utf8)!
        let manifestJSON =
            #"{"id":"legacy","name":"Legacy","icon":"app","description":"Old","apiVersion":1,"sha256":"def456"}"#.data(
                using: .utf8)!
        let http = StubHTTPClient(responses: [rel: .success(releaseJSON), man: .success(manifestJSON)])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/legacy"], http: http)
        let entries = try await source.fetchCatalog()
        #expect(entries.first?.author == nil)
        #expect(entries.first?.longDescription == nil)
        #expect(entries.first?.screenshots == [])
        #expect(entries.first?.links == [])
    }
}
