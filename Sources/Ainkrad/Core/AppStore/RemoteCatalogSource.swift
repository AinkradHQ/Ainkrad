import AinkradHostRuntime
import Foundation

/// Where the App Store's catalog comes from. `RemoteCatalogSource` is the
/// production conformer; tests supply stubs.
protocol CatalogSource {
    func fetchCatalog() async throws -> [CatalogEntry]
    /// Apps and themes from one fetch of the catalog document.
    func fetchCatalogAndThemes() async throws -> (apps: [CatalogEntry], themes: [ThemeCatalogEntry])
}

extension CatalogSource {
    /// Sources without themes (test stubs) list none.
    func fetchCatalogAndThemes() async throws -> (apps: [CatalogEntry], themes: [ThemeCatalogEntry]) {
        (try await fetchCatalog(), [])
    }
}

/// The hosted `catalog.json` document (the central AinkradCatalog).
/// `themes` (schema 2) is decoded per element and never fails the apps;
/// it is nil for a schema-1 catalog.
struct RemoteCatalog: Decodable {
    let schemaVersion: Int?
    let apps: [CatalogEntry]
    let themes: [ThemeCatalogEntry]?

    private enum CodingKeys: String, CodingKey { case schemaVersion, apps, themes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
        apps = try c.decode([CatalogEntry].self, forKey: .apps)
        do {
            themes = try c.decodeIfPresent([FailableThemeCatalogEntry].self, forKey: .themes)?.compactMap(\.entry)
        } catch {
            Log.appStore.error("Ignoring malformed themes array: \(String(describing: error), privacy: .public)")
            themes = nil
        }
    }
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
        try await fetchDocument().apps
    }

    func fetchCatalogAndThemes() async throws -> (apps: [CatalogEntry], themes: [ThemeCatalogEntry]) {
        let document = try await fetchDocument()
        return (document.apps, document.themes ?? [])
    }

    private func fetchDocument() async throws -> RemoteCatalog {
        try JSONDecoder().decode(RemoteCatalog.self, from: try await http.get(url))
    }
}
