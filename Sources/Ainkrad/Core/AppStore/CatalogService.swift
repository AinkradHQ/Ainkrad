import AinkradHostRuntime
import Foundation

/// Persisted snapshot of the last successfully-fetched catalog (offline fallback).
struct CatalogCacheDocument: PersistableDocument {
    static let documentID = "marketplace-catalog-cache"
    var entries: [CatalogEntry] = []
}

/// Fetches the catalog and caches it; returns the cache when a fetch fails.
@MainActor
final class CatalogService {
    // `CatalogSource` is a plain (non-Sendable) protocol; conformers used here
    // (GitHub-backed source, test stubs) are immutable value types, so a
    // stored `let` is safe to hand across the actor boundary for the await.
    private nonisolated(unsafe) let source: CatalogSource
    private let persistence: PersistenceStore

    init(source: CatalogSource, persistence: PersistenceStore) {
        self.source = source
        self.persistence = persistence
    }

    var cached: [CatalogEntry] { persistence.load(CatalogCacheDocument.self)?.entries ?? [] }

    /// Fetch → cache + return on success; return the last cache on failure.
    func refresh() async -> [CatalogEntry] {
        do {
            let entries = try await source.fetchCatalog()
            persistence.save(CatalogCacheDocument(entries: entries))
            return entries
        } catch {
            Log.appStore.error("Catalog refresh failed, using cache: \(String(describing: error), privacy: .public)")
            return cached
        }
    }
}
