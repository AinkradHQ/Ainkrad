// Sources/Ainkrad/Core/AgentKit/Composer/WorkspaceFileIndex.swift
import Foundation

struct FileMatch: Equatable, Sendable {
    let path: String
    let name: String
    let score: Int
}

@MainActor
final class WorkspaceFileIndex {
    private let root: URL
    private let fm: FileManager
    private let maxFiles: Int
    private var paths: [String] = []
    nonisolated static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", ".swiftpm",
    ]

    init(root: URL, fileManager: FileManager = .default, maxFiles: Int = 20_000) {
        self.root = root
        self.fm = fileManager
        self.maxFiles = maxFiles
    }

    /// Shared traversal so every workspace tool (index, grep, glob) honors the
    /// SAME ignore rules — never a divergent second copy.
    // `nonisolated`: this is a pure traversal over `root`/`fileManager` args and the
    // immutable `ignoredDirectories` set — no instance/actor state touched. Search
    // tools (grep/glob) call it from a detached background task to keep the walk
    // off the @MainActor for large/adversarial trees.
    nonisolated static func fileURLs(
        under root: URL, fileManager: FileManager = .default,
        maxFiles: Int = 100_000
    ) -> [URL] {
        var out: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let en = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        for case let url as URL in en {
            if ignoredDirectories.contains(url.lastPathComponent) {
                en.skipDescendants()
                continue
            }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                out.append(url)
                if out.count >= maxFiles { break }
            }
        }
        return out
    }

    /// Rebuilds the index, walking the tree **off the main actor**.
    ///
    /// The walk itself is `nonisolated` and always was — but the previous
    /// caller was `Task { workspaceFileIndex.refresh() }` from a `@MainActor`
    /// context, and an unqualified `Task` *inherits* the enclosing actor
    /// isolation. So the comment there ("keeps bootstrap's synchronous path
    /// from stalling") was wrong: the walk still ran on the main actor, just
    /// one turn later. With the root defaulting to the home directory, that was
    /// a 20,000-file enumeration of `~` blocking the first frames.
    ///
    /// Only the assignment comes back to the actor.
    func refresh() async {
        let root = self.root
        let maxFiles = self.maxFiles
        // A fresh `FileManager` rather than the shared instance: `FileManager`
        // is not `Sendable`, and a per-task instance is the documented way to
        // use one off the main thread.
        let found = await Task.detached(priority: .utility) {
            Self.fileURLs(under: root, fileManager: FileManager(), maxFiles: maxFiles).map(\.path)
        }.value
        paths = found
    }

    /// Synchronous rebuild, for tests and for callers already off the hot path.
    func refreshSynchronously() {
        paths = Self.fileURLs(under: root, fileManager: fm, maxFiles: maxFiles).map(\.path)
    }

    func search(_ query: String, limit: Int = 12) -> [FileMatch] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        return paths.compactMap { path -> FileMatch? in
            let name = (path as NSString).lastPathComponent
            guard let score = Self.fuzzyScore(query: q, target: path.lowercased(), basename: name.lowercased()) else {
                return nil
            }
            return FileMatch(path: path, name: name, score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit).map { $0 }
    }

    /// Subsequence match; +bonus for contiguous runs and basename hits.
    private static func fuzzyScore(query: String, target: String, basename: String) -> Int? {
        var qi = query.startIndex
        var score = 0
        var streak = 0
        for ch in target {
            guard qi < query.endIndex else { break }
            if ch == query[qi] {
                streak += 1
                score += 1 + streak
                qi = query.index(after: qi)
            } else {
                streak = 0
            }
        }
        guard qi == query.endIndex else { return nil }
        if basename.contains(query) { score += 10 }
        return score
    }
}
