import Foundation
import Testing

@testable import Ainkrad

/// Canned `git` output, counting invocations so cache behaviour is testable.
private final class StubGitRunner: GitRunning, @unchecked Sendable {
    var output: String
    private(set) var invocations = 0
    var shouldThrow = false

    init(output: String) { self.output = output }

    func run(_ args: [String], in directory: URL) throws -> String {
        invocations += 1
        if shouldThrow { throw GitRunFailure(status: 128, stderr: "not a repository") }
        return output
    }
}

@MainActor
@Suite("GitStatusProvider")
struct GitStatusProviderTests {
    private func makeFS(withRepoAt repoPath: String?) -> InMemoryFileSystem {
        let fs = InMemoryFileSystem(home: URL(fileURLWithPath: "/Users/test"))
        fs.add(directory: "/Users/test/project", children: ["src/", "README.md"])
        fs.add(directory: "/Users/test/project/src", children: ["main.swift"])
        fs.add(directory: "/Users/test/plain", children: ["a.txt"])
        if let repoPath {
            // `.git` present marks the repo root. A FILE, not a directory —
            // worktrees and submodules use a gitfile, and discovery must
            // accept both.
            fs.add(directory: repoPath, children: [".git", "src/", "README.md"])
        }
        return fs
    }

    private let sampleOutput = """
        # branch.head main
        1 .M N... 100644 100644 100644 a b src/main.swift
        """

    @Test("discovery finds the enclosing repo from a nested directory")
    func discoversFromNested() {
        let fs = makeFS(withRepoAt: "/Users/test/project")
        let root = discoverRepositoryRoot(
            for: URL(fileURLWithPath: "/Users/test/project/src"), fileSystem: fs)
        #expect(root == URL(fileURLWithPath: "/Users/test/project"))
    }

    @Test("discovery returns nil outside any repo")
    func discoveryOutsideRepo() {
        let fs = makeFS(withRepoAt: nil)
        #expect(
            discoverRepositoryRoot(
                for: URL(fileURLWithPath: "/Users/test/plain"), fileSystem: fs) == nil)
    }

    @Test("discovery terminates at the filesystem root instead of looping")
    func discoveryTerminates() {
        let fs = makeFS(withRepoAt: nil)
        #expect(discoverRepositoryRoot(for: URL(fileURLWithPath: "/"), fileSystem: fs) == nil)
    }

    @Test("a refresh populates the cache and reports status per file")
    func refreshPopulates() async {
        let fs = makeFS(withRepoAt: "/Users/test/project")
        let runner = StubGitRunner(output: sampleOutput)
        let provider = GitStatusProvider(runner: runner, fileSystem: fs)

        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/project"))

        #expect(provider.status(forDirectory: URL(fileURLWithPath: "/Users/test/project"))?.branch == "main")
        #expect(provider.status(for: URL(fileURLWithPath: "/Users/test/project/src/main.swift")) == .modified)
    }

    // The whole point of the cache: a listing re-renders per keystroke, and
    // each refresh is a process spawn.
    @Test("a warm cache does not spawn git again")
    func cacheHitDoesNotSpawn() async {
        let fs = makeFS(withRepoAt: "/Users/test/project")
        let runner = StubGitRunner(output: sampleOutput)
        let provider = GitStatusProvider(runner: runner, fileSystem: fs)

        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/project"))
        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/project"))
        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/project/src"))

        #expect(runner.invocations == 1)
    }

    @Test("invalidate forces the next refresh to spawn")
    func invalidateForcesRefresh() async {
        let fs = makeFS(withRepoAt: "/Users/test/project")
        let runner = StubGitRunner(output: sampleOutput)
        let provider = GitStatusProvider(runner: runner, fileSystem: fs)
        let root = URL(fileURLWithPath: "/Users/test/project")

        await provider.refreshIfNeeded(directory: root)
        provider.invalidate(root: root)
        await provider.refreshIfNeeded(directory: root)

        #expect(runner.invocations == 2)
    }

    // Without caching the negative, browsing outside a repo re-walks the whole
    // tree looking for `.git` on every navigation.
    @Test("a non-repo directory is remembered and never spawns git")
    func nonRepoCachedNegatively() async {
        let fs = makeFS(withRepoAt: nil)
        let runner = StubGitRunner(output: sampleOutput)
        let provider = GitStatusProvider(runner: runner, fileSystem: fs)

        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/plain"))
        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/plain"))

        #expect(runner.invocations == 0)
        #expect(provider.status(forDirectory: URL(fileURLWithPath: "/Users/test/plain")) == nil)
    }

    @Test("a git failure degrades to no badges rather than breaking the listing")
    func failureDegrades() async {
        let fs = makeFS(withRepoAt: "/Users/test/project")
        let runner = StubGitRunner(output: sampleOutput)
        runner.shouldThrow = true
        let provider = GitStatusProvider(runner: runner, fileSystem: fs)

        await provider.refreshIfNeeded(directory: URL(fileURLWithPath: "/Users/test/project"))

        #expect(provider.status(forDirectory: URL(fileURLWithPath: "/Users/test/project")) == nil)
    }
}
