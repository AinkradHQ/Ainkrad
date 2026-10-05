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
}
