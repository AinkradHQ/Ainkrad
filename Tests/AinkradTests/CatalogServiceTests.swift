import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
struct CatalogServiceTests {
    private func entry(_ id: String) -> CatalogEntry {
        CatalogEntry(
            appID: id, displayName: id, icon: "app", description: "", version: "1.0.0",
            apiVersion: 1, downloadURL: URL(string: "https://e/\(id).zip")!, sha256: "x", sourceRepo: "o/\(id)")
    }
    struct StubSource: CatalogSource {
        var result: Result<[CatalogEntry], Error>
        func fetchCatalog() async throws -> [CatalogEntry] {
            switch result {
            case .success(let e): return e
            case .failure(let e): throw e
            }
        }
    }
    struct Boom: Error {}

    @Test("refresh success caches and returns the catalog")
    func refreshCaches() async {
        let store = InMemoryPersistenceStore()
        let svc = CatalogService(source: StubSource(result: .success([entry("a")])), persistence: store)
        let got = await svc.refresh()
        #expect(got.map(\.appID) == ["a"])
        #expect(store.load(CatalogCacheDocument.self)?.entries.map(\.appID) == ["a"])
    }

    @Test("refresh failure falls back to the last cache")
    func offlineFallback() async {
        let store = InMemoryPersistenceStore()
        store.save(CatalogCacheDocument(entries: [entry("cached")]))
        let svc = CatalogService(source: StubSource(result: .failure(Boom())), persistence: store)
        let got = await svc.refresh()
        #expect(got.map(\.appID) == ["cached"])
    }

    // MARK: - Themes (schema 2)

    private let url = URL(string: "https://example.com/catalog.json")!

    private func service(_ http: StubHTTPClient, _ store: InMemoryPersistenceStore) -> CatalogService {
        CatalogService(source: RemoteCatalogSource(url: url, http: http), persistence: store)
    }

    @Test("refresh caches themes and hides entries with a newer format; apps unchanged")
    func refreshCachesThemes() async {
        let store = InMemoryPersistenceStore()
        let svc = service(StubHTTPClient(responses: [url: .success(RemoteCatalogSourceTests.schema2Fixture)]), store)
        let apps = await svc.refresh()
        #expect(apps.map(\.appID) == ["gitmage"])
        #expect(svc.themes.map(\.id) == ["glass"])
        #expect(store.load(ThemeCatalogCacheDocument.self)?.entries.map(\.id) == ["glass", "future"])
    }

    @Test("with the network failing, the cached themes are returned")
    func themesOfflineFallback() async {
        let store = InMemoryPersistenceStore()
        _ = await service(StubHTTPClient(responses: [url: .success(RemoteCatalogSourceTests.schema2Fixture)]), store)
            .refresh()

        let svc = service(StubHTTPClient(responses: [url: .failure(HTTPError.status(503))]), store)
        let apps = await svc.refresh()
        #expect(apps.map(\.appID) == ["gitmage"])
        #expect(svc.themes.map(\.id) == ["glass"])
    }

    @Test("a v1 catalog lists no themes and clears a stale theme cache")
    func v1CatalogHasNoThemes() async {
        let store = InMemoryPersistenceStore()
        _ = await service(StubHTTPClient(responses: [url: .success(RemoteCatalogSourceTests.schema2Fixture)]), store)
            .refresh()

        let v1 = #"{"schemaVersion":1,"apps":[]}"#.data(using: .utf8)!
        let svc = service(StubHTTPClient(responses: [url: .success(v1)]), store)
        _ = await svc.refresh()
        #expect(svc.themes.isEmpty)
    }

    @Test("a source without themes (stub) lists none")
    func stubSourceHasNoThemes() async {
        let svc = CatalogService(
            source: StubSource(result: .success([entry("a")])), persistence: InMemoryPersistenceStore())
        _ = await svc.refresh()
        #expect(svc.themes.isEmpty)
    }
}
