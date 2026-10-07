import Foundation
import Testing

@testable import Ainkrad

/// AIN-147: the app detail page's catalog metadata — `author`,
/// `longDescription`, `screenshots`, `links` — on `CatalogEntry`. All of them
/// are optional so pre-existing catalogs and caches keep decoding unchanged.
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
}
