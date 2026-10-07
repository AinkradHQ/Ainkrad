import Foundation
import Observation

/// Per-repo git status with caching and explicit invalidation.
///
/// Caching is not an optimisation here, it is the design: every status refresh
/// is a process spawn, and a directory listing re-renders on every keystroke.
/// Without a cache, arrowing through a repo would fork `git` per row.
@MainActor
@Observable
final class GitStatusProvider {
    private let runner: any GitRunning
    private let fileSystem: any FileSystemServing

    /// repo root path → status.
    private var cache: [String: GitRepoStatus] = [:]
    /// Directories already known NOT to be in a repo. Cached deliberately:
    /// without this, browsing outside a repo re-probes for `.git` up the whole
    /// tree on every navigation.
    private var knownNonRepos: Set<String> = []

    init(
        runner: any GitRunning = SystemGitRunner(),
        fileSystem: any FileSystemServing
    ) {
        self.runner = runner
        self.fileSystem = fileSystem
    }

    /// Every repo root seen so far this session, for the sidebar's
    /// Repositories group.
    ///
    /// Deliberately "repos you have visited", not "repos on this machine":
    /// finding the latter means walking the entire home folder looking for
    /// `.git`, which is minutes of I/O to populate a sidebar. This costs
    /// nothing and converges on the repos the user actually works in.
    var knownRepositoryRoots: [URL] {
        cache.keys.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Cached status for the repo enclosing `directory`, or `nil` when it
    /// isn't in a repo or nothing has been fetched yet. Never spawns.
    func status(forDirectory directory: URL) -> GitRepoStatus? {
        guard let root = repositoryRoot(for: directory) else { return nil }
        return cache[root.path]
    }

    /// Status for one file, for the row gutter.
    func status(for url: URL) -> GitFileStatus? {
        status(forDirectory: url.deletingLastPathComponent())?.status(for: url)
    }

    /// Fetches if not already cached. Safe to call on every navigation — it is
    /// a no-op once warm.
    func refreshIfNeeded(directory: URL) async {
        guard let root = repositoryRoot(for: directory) else { return }
        guard cache[root.path] == nil else { return }
        await refresh(root: root)
    }

    /// Unconditional re-fetch. Called from the FSEvents watcher, whose 200ms
    /// coalescing is what keeps a `git checkout` from spawning hundreds.
    func refresh(directory: URL) async {
        guard let root = repositoryRoot(for: directory) else { return }
        await refresh(root: root)
    }

    func invalidate(root: URL) {
        cache[root.path] = nil
    }

    private func refresh(root: URL) async {
        let runner = self.runner
        // Off the main actor: the spawn blocks until git exits, and a large
        // repo's status is not instant.
        let output: String? = await Task.detached {
            try? runner.run(
                ["status", "--porcelain=v2", "--branch", "--ignored=matching"], in: root)
        }.value

        // Degrade silently: no git, no permission, not a repo after all — all
        // mean no badges, never a broken listing.
        guard let output else { return }
        cache[root.path] = parsePorcelainV2(output, root: root)
    }

    private func repositoryRoot(for directory: URL) -> URL? {
        let path = directory.standardizedFileURL.path
        if knownNonRepos.contains(path) { return nil }

        // A cached repo whose root is a prefix answers without walking again.
        if let hit = cache.keys.first(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return URL(fileURLWithPath: hit)
        }

        guard let root = discoverRepositoryRoot(for: directory, fileSystem: fileSystem) else {
            knownNonRepos.insert(path)
            return nil
        }
        return root
    }
}
