import Foundation
import Testing

@testable import Ainkrad

/// HTTPClient stub returning canned bytes per URL (or an error).
struct StubHTTPClient: HTTPClient {
    var responses: [URL: Result<Data, Error>]
    struct NoStub: Error {}
    func get(_ url: URL) async throws -> Data {
        switch responses[url] {
        case .success(let d): return d
        case .failure(let e): throw e
        case nil: throw NoStub()
        }
    }
}

struct GitHubCatalogSourceTests {
    private func releaseJSON(zip: String, manifest: String) -> Data {
        """
        {"tag_name":"1.2.0","assets":[
          {"name":"ainkrad-plugin.json","browser_download_url":"\(manifest)"},
          {"name":"Hello.bundle.zip","browser_download_url":"\(zip)"}]}
        """.data(using: .utf8)!
    }
    private func manifestJSON() -> Data {
        """
        {"id":"hello","name":"Hello","icon":"hand.wave","description":"Hi","apiVersion":1,"sha256":"abc123"}
        """.data(using: .utf8)!
    }

    @Test("assembles a CatalogEntry from a repo's latest release")
    func assembles() async throws {
        let rel = URL(string: "https://api.github.com/repos/acme/hello/releases/latest")!
        let man = URL(string: "https://example.com/ainkrad-plugin.json")!
        let zip = URL(string: "https://example.com/Hello.bundle.zip")!
        let http = StubHTTPClient(responses: [
            rel: .success(releaseJSON(zip: zip.absoluteString, manifest: man.absoluteString)),
            man: .success(manifestJSON()),
        ])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/hello"], http: http)
        let entries = try await source.fetchCatalog()
        #expect(
            entries == [
                CatalogEntry(
                    appID: "hello", displayName: "Hello", icon: "hand.wave",
                    description: "Hi", version: "1.2.0", apiVersion: 1, downloadURL: zip, sha256: "abc123",
                    sourceRepo: "acme/hello")
            ])
    }

    @Test("a failing repo is skipped, others still returned")
    func skipsBadRepo() async throws {
        let relOK = URL(string: "https://api.github.com/repos/acme/hello/releases/latest")!
        let man = URL(string: "https://example.com/ainkrad-plugin.json")!
        let zip = URL(string: "https://example.com/Hello.bundle.zip")!
        struct Boom: Error {}
        let http = StubHTTPClient(responses: [
            relOK: .success(releaseJSON(zip: zip.absoluteString, manifest: man.absoluteString)),
            man: .success(manifestJSON()),
            URL(string: "https://api.github.com/repos/acme/broken/releases/latest")!: .failure(Boom()),
        ])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/broken", "acme/hello"], http: http)
        let entries = try await source.fetchCatalog()
        #expect(entries.map(\.appID) == ["hello"])
    }

    @Test("a release missing the manifest asset is skipped; a healthy repo still returns")
    func missingManifestAsset() async throws {
        let relBad = URL(string: "https://api.github.com/repos/acme/bad/releases/latest")!
        let relOK = URL(string: "https://api.github.com/repos/acme/hello/releases/latest")!
        let man = URL(string: "https://example.com/ainkrad-plugin.json")!
        let zip = URL(string: "https://example.com/Hello.bundle.zip")!
        let noManifest =
            #"{"tag_name":"1.0.0","assets":[{"name":"Hello.bundle.zip","browser_download_url":"https://x/z.zip"}]}"#
            .data(using: .utf8)!
        let http = StubHTTPClient(responses: [
            relBad: .success(noManifest),
            relOK: .success(releaseJSON(zip: zip.absoluteString, manifest: man.absoluteString)),
            man: .success(manifestJSON()),
        ])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/bad", "acme/hello"], http: http)
        #expect(try await source.fetchCatalog().map(\.appID) == ["hello"])
    }

    @Test("a release missing the .bundle.zip asset is skipped")
    func missingZipAsset() async throws {
        let relBad = URL(string: "https://api.github.com/repos/acme/bad/releases/latest")!
        let noZip =
            #"{"tag_name":"1.0.0","assets":[{"name":"ainkrad-plugin.json","browser_download_url":"https://x/m.json"}]}"#
            .data(using: .utf8)!
        let http = StubHTTPClient(responses: [relBad: .success(noZip)])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/bad"], http: http)
        #expect(try await source.fetchCatalog().isEmpty)
    }

    @Test("a malformed manifest JSON skips that repo")
    func malformedManifest() async throws {
        let rel = URL(string: "https://api.github.com/repos/acme/bad/releases/latest")!
        let man = URL(string: "https://example.com/ainkrad-plugin.json")!
        let zip = URL(string: "https://example.com/Hello.bundle.zip")!
        let http = StubHTTPClient(responses: [
            rel: .success(releaseJSON(zip: zip.absoluteString, manifest: man.absoluteString)),
            man: .success(Data("{ not json".utf8)),
        ])
        let source = GitHubReleasesCatalogSource(repositories: ["acme/bad"], http: http)
        #expect(try await source.fetchCatalog().isEmpty)
    }
}
