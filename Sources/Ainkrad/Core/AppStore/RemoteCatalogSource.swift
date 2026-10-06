import Foundation

/// Where the App Store's catalog comes from. `RemoteCatalogSource` is the
/// production conformer; tests supply stubs.
protocol CatalogSource {
    func fetchCatalog() async throws -> [CatalogEntry]
}

/// The hosted `catalog.json` document (the central AinkradCatalog).
struct RemoteCatalog: Decodable {
    let schemaVersion: Int?
    let apps: [CatalogEntry]
}

/// Loads the full app catalog from a single hosted `catalog.json`. App
/// presentation (name/description/screenshots/links) *and* downloads
/// (version/downloadURL/sha256) live there, so adding an app or shipping a new
/// version needs only a catalog edit — no Ainkrad host release. Offline
/// fallback to the last cached catalog is handled by `CatalogService`.
struct RemoteCatalogSource: CatalogSource {
    let url: URL
    let http: HTTPClient

    func fetchCatalog() async throws -> [CatalogEntry] {
        let data = try await http.get(url)
        return try JSONDecoder().decode(RemoteCatalog.self, from: data).apps
    }
}
