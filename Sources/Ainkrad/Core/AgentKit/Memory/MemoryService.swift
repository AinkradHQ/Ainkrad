import AinkradHostRuntime
import Foundation

/// The single facade over the host-internal memory subsystem: composes
/// `MemoryStore` (file I/O), `MemoryIndex` (FTS search), and `MemoryLogStore`
/// (provenance + undo). Coordinates a write so the index is updated and the
/// log records provenance + prior snapshot in one call. Injected wherever
/// memory is read or written.
@MainActor
final class MemoryService {
    let store: MemoryStore
    let log: MemoryLogStore
    private let index: MemoryIndex

    init(paths: MemoryPaths, persistence: PersistenceStore) throws {
        self.store = MemoryStore(paths: paths)
        self.index = try MemoryIndex(url: paths.indexURL)
        self.log = MemoryLogStore(persistence: persistence, memory: store)
        store.onChange = { [weak self] file in self?.reindex(file) }
        rebuildIndex()
    }

    func write(_ text: String, to file: MemoryFile, provenance: MemoryProvenance) {
        let prior = store.read(file)
        store.append(text, to: file)  // triggers onChange → reindex
        log.record(file: file, provenance: provenance, addedText: text, priorSnapshot: prior)
    }

    func search(_ query: String, limit: Int = 20) -> [MemorySearchHit] {
        index.search(query, limit: limit)
    }

    func alwaysLoaded() -> [(MemoryFile, String)] { store.alwaysLoadedSet() }

    func rebuildIndex() {
        index.clear()
        for file in MemoryFile.allCases { reindex(file) }
    }

    private func reindex(_ file: MemoryFile) {
        index.upsert(source: file.rawValue, title: file.rawValue, body: store.read(file))
    }
}
