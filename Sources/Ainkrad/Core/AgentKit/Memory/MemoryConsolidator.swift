import Foundation

/// Cheap rule-based consolidation pass run on every settled turn: dedupes
/// exact-duplicate lines in MEMORY.md (order-preserving) and tail-caps the
/// total line count. Writes ONLY when content actually changed, so a no-op
/// settle never churns the write path, the search index, or the audit log.
/// LLM-powered merge and the `sessions/<id>.md` rollup are deferred.
enum MemoryConsolidator {
    @MainActor
    static func consolidate(_ service: MemoryService, maxLines: Int = 500) {
        let original = service.store.read(.memory)
        let lines = original.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var seen = Set<String>()
        var deduped: [String] = []
        for line in lines where seen.insert(line).inserted { deduped.append(line) }
        let capped = deduped.count > maxLines ? Array(deduped.suffix(maxLines)) : deduped
        let result = capped.joined(separator: "\n")
        guard result != original else { return }  // no-op turn → no write/reindex/log churn
        service.store.write(result, to: .memory)  // onChange reindexes
        service.log.record(
            file: .memory, provenance: .consolidation,
            addedText: "(consolidation: deduped/capped MEMORY.md)",
            priorSnapshot: original)
    }
}
