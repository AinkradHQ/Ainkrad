import Foundation

/// One search hit.
struct SearchHit: Identifiable, Equatable, Sendable {
    var entry: FileEntry
    /// Directory containing the hit, relative to the search root — the column
    /// that tells you WHERE something was found, which is most of the value of
    /// a recursive search.
    var relativeDirectory: String

    var id: URL { entry.url }
}

/// What to look for.
struct SearchQuery: Equatable, Sendable {
    var text: String
    var caseSensitive = false
    /// Search inside ignored/hidden directories. Off by default: recursing
    /// into `node_modules`, `.git` and `build` is what makes naive file search
    /// feel broken.
    var includeHidden = false
    /// Hard ceiling on results. An unbounded search that finds 400,000 matches
    /// is not more useful than one that finds 500 — it just hangs.
    var limit = 500
    /// Hard ceiling on directory depth, so a symlink loop or a pathological
    /// tree cannot run forever.
    var maxDepth = 12
    /// Collect EVERY entry rather than filtering by `text`.
    ///
    /// The jump palette (⌘P) needs the whole candidate set to rank in memory,
    /// but an empty `text` must keep meaning "find nothing" for a search — an
    /// empty search box returning the entire disk is a bug, not a feature. So
    /// match-all is an explicit mode, never an inferred one.
    var matchAll = false
}

/// Directory names never descended into, regardless of hidden settings. These
/// are where recursive search goes to die: a single `node_modules` can hold
/// more entries than the rest of a project combined.
private let prunedDirectories: Set<String> = [
    ".git", "node_modules", ".build", "build", "DerivedData",
    ".next", "dist", "target", "Pods", ".venv", "venv", "__pycache__",
]

/// Does `name` match `query`?
///
/// Substring, not fuzzy: a file search that matches "abc" against "a-b-c.txt"
/// produces results the user cannot predict. The fuzzy matcher is a separate
/// affordance (⌘P) where surprise is the point.
func matchesSearch(name: String, query: SearchQuery) -> Bool {
    if query.matchAll { return true }
    guard !query.text.isEmpty else { return false }
    if query.caseSensitive { return name.contains(query.text) }
    return name.lowercased().contains(query.text.lowercased())
}

/// Recursively searches `root`, calling `isCancelled` between directories.
///
/// Breadth-first, deliberately: results from the top of the tree are the ones
/// most likely to be wanted, and they arrive first. A depth-first walk would
/// spend its budget deep inside the first subtree it happened to enter.
func searchFiles(
    root: URL, query: SearchQuery, fileSystem: any FileSystemServing,
    isCancelled: () -> Bool = { false },
    onBatch: (([SearchHit]) -> Void)? = nil
) -> [SearchHit] {
    guard query.matchAll || !query.text.isEmpty else { return [] }

    var hits: [SearchHit] = []
    var queue: [(url: URL, depth: Int)] = [(root, 0)]
    let rootPath = root.standardizedFileURL.path

    // Results are reported as each directory completes rather than only at the
    // end. A recursive walk over a large tree takes seconds, and showing
    // nothing until it finishes is what made search feel broken and slow —
    // the first useful hits are usually found in the first few milliseconds.
    var pending: [SearchHit] = []

    while !queue.isEmpty {
        if isCancelled() || hits.count >= query.limit { break }
        let (directory, depth) = queue.removeFirst()

        guard let entries = try? fileSystem.contents(of: directory) else { continue }

        for entry in entries {
            if hits.count >= query.limit { break }

            if !query.includeHidden && entry.isHidden { continue }

            if matchesSearch(name: entry.name, query: query) {
                let hit = SearchHit(
                    entry: entry,
                    relativeDirectory: relativePath(of: directory, from: rootPath))
                hits.append(hit)
                pending.append(hit)
            }

            if entry.isDirectory, depth + 1 <= query.maxDepth,
                !prunedDirectories.contains(entry.name),
                // Following symlinked directories is how a search finds a cycle
                // and never returns.
                !entry.isSymlink
            {
                queue.append((entry.url, depth + 1))
            }
        }

        if let onBatch, !pending.isEmpty {
            onBatch(pending)
            pending = []
        }
    }
    if let onBatch, !pending.isEmpty { onBatch(pending) }
    return hits
}

private func relativePath(of directory: URL, from rootPath: String) -> String {
    let path = directory.standardizedFileURL.path
    guard path.hasPrefix(rootPath) else { return path }
    var relative = String(path.dropFirst(rootPath.count))
    if relative.hasPrefix("/") { relative.removeFirst() }
    return relative.isEmpty ? "." : relative
}
