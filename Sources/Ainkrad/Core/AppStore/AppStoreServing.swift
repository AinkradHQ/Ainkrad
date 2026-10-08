import Foundation

/// The catalog+install surface the App Store UI depends on. `AppStoreService`
/// conforms; tests use a fake so the store is unit-testable without network/fs.
@MainActor
protocol AppStoreServing {
    var cachedCatalog: [CatalogEntry] { get }
    func refreshCatalog() async -> [CatalogEntry]
    func install(appID: String) async throws
    func update(appID: String) async throws
    func uninstall(appID: String) throws
    func installedApps() -> [String: InstalledPluginsDocument.Entry]
    func availableUpdates() -> [CatalogEntry]
    func hasRetainedData(appID: String) -> Bool
    func restoreRetainedData(appID: String)
    func discardRetainedData(appID: String)
    /// The store's compatible themes and colour schemes (cached, so offline too).
    var themeCatalog: [ThemeCatalogEntry] { get }
    func installedThemes() -> [String: InstalledThemesDocument.Entry]
    /// Installs or updates (replaces) a theme or colour scheme.
    func installTheme(_ entry: ThemeCatalogEntry) async throws
    func uninstallTheme(id: String) throws
}

/// No themes by default, so app-only fakes stay unchanged.
extension AppStoreServing {
    var themeCatalog: [ThemeCatalogEntry] { [] }
    func installedThemes() -> [String: InstalledThemesDocument.Entry] { [:] }
    func installTheme(_ entry: ThemeCatalogEntry) async throws {
        throw AppStoreError.invalidBundle("theme installer unavailable")
    }
    func uninstallTheme(id: String) throws { throw AppStoreError.notInstalled(id) }
}
