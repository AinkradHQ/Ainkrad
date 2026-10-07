import Foundation
import Testing

@testable import Ainkrad

@Suite struct RepoInstructionWalkerTests {
    private func makeTree() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = base.appendingPathComponent("repo/src")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("root claude".utf8).write(to: base.appendingPathComponent("repo/CLAUDE.md"))
        try Data("root agents".utf8).write(to: base.appendingPathComponent("repo/AGENTS.md"))
        return sub
    }

    @Test func findsFilesWalkingUpNearestFirst() throws {
        let start = try makeTree()
        let found = RepoInstructionWalker.instructionFiles(startingAt: start)
        #expect(found.map { $0.lastPathComponent } == ["CLAUDE.md", "AGENTS.md"])
    }

    @Test func returnsEmptyWhenNoneFound() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(RepoInstructionWalker.instructionFiles(startingAt: empty, maxDepth: 2).isEmpty)
    }

    @Test func respectsMaxDepth() throws {
        let start = try makeTree()  // file is one level above `start`
        #expect(RepoInstructionWalker.instructionFiles(startingAt: start, maxDepth: 1).isEmpty)
    }

    @Test func stopsAtRepoRootDotGit() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = base.appendingPathComponent("repo")
        let src = repo.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        // instruction files at BOTH the repo root and ABOVE it (in base):
        try Data("repo rules".utf8).write(to: repo.appendingPathComponent("CLAUDE.md"))
        try Data("outside rules".utf8).write(to: base.appendingPathComponent("CLAUDE.md"))
        defer { try? FileManager.default.removeItem(at: base) }
        let found = RepoInstructionWalker.instructionFiles(startingAt: src)
        // includes the repo-root CLAUDE.md, but NOT the one above the repo root:
        #expect(found.contains { $0.path == repo.appendingPathComponent("CLAUDE.md").path })
        #expect(!found.contains { $0.path == base.appendingPathComponent("CLAUDE.md").path })
    }

    @Test func dotGitAsFileAlsoBounds() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Data("gitdir: /elsewhere".utf8).write(to: repo.appendingPathComponent(".git"))  // worktree-style .git FILE
        try Data("repo rules".utf8).write(to: repo.appendingPathComponent("CLAUDE.md"))
        try Data("outside".utf8).write(to: base.appendingPathComponent("CLAUDE.md"))
        defer { try? FileManager.default.removeItem(at: base) }
        let found = RepoInstructionWalker.instructionFiles(startingAt: repo)
        #expect(found.contains { $0.path == repo.appendingPathComponent("CLAUDE.md").path })
        #expect(!found.contains { $0.path == base.appendingPathComponent("CLAUDE.md").path })
    }
}
