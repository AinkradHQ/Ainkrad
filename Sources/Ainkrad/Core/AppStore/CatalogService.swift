import AinkradHostRuntime
import Foundation

/// Persisted snapshot of the last successfully-fetched catalog (offline fallback).
struct CatalogCacheDocument: PersistableDocument {
    static let documentID = "marketplace-catalog-cache"
    var entries: [CatalogEntry] = []
}

/// Persisted snapshot of the last fetched `themes` array, kept apart from
/// `CatalogCacheDocument` so existing caches still decode.
struct ThemeCatalogCacheDocument: PersistableDocument {
    static let documentID = "marketplace-theme-cache"
    var entries: [ThemeCatalogEntry] = []
}

/// Fetches the catalog and caches it; returns the cache when a fetch fails.
@MainActor
final class CatalogService {
    // `CatalogSource` is a plain (non-Sendable) protocol; conformers used here
    // (`RemoteCatalogSource`, test stubs) are immutable value types, so a
    // stored `let` is safe to hand across the actor boundary for the await.
    private nonisolated(unsafe) let source: CatalogSource
    private let persistence: PersistenceStore

    init(source: CatalogSource, persistence: PersistenceStore) {
        self.source = source
        self.persistence = persistence
    }

    var cached: [CatalogEntry] { persistence.load(CatalogCacheDocument.self)?.entries ?? [] }

    /// The store's themes from the last successful refresh (the cache, so offline too),
    /// minus entries that need a newer theme format than this host reads.
    var themes: [ThemeCatalogEntry] {
        (persistence.load(ThemeCatalogCacheDocument.self)?.entries ?? []).filter(\.isCompatible)
    }

    /// Fetch → cache + return on success; return the last cache on failure.
    /// Themes are cached from the same fetch; read them from `themes`.
    func refresh() async -> [CatalogEntry] {
        do {
            let (entries, themeEntries) = try await source.fetchCatalogAndThemes()
            persistence.save(CatalogCacheDocument(entries: entries))
            persistence.save(ThemeCatalogCacheDocument(entries: themeEntries))
            return entries
        } catch {
            Log.appStore.error("Catalog refresh failed, using cache: \(String(describing: error), privacy: .public)")
            return cached
        }
    }
}
