import Foundation
import Testing

@testable import Ainkrad

/// End-to-end against a REAL `git`, in a throwaway repo.
///
/// The parser tests cover the format exhaustively from fixtures, but fixtures
/// only prove the parser matches what I believed git emits. This proves it
/// matches what git actually emits on this machine — the gap that hand-written
/// fixtures cannot close.
@MainActor
@Suite("Git integration", .serialized)
struct GitIntegrationTests {
    private func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-itest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let runner = SystemGitRunner()
        _ = try runner.run(["init", "--initial-branch=main"], in: root)
        _ = try runner.run(["config", "user.email", "test@example.com"], in: root)
        _ = try runner.run(["config", "user.name", "Test"], in: root)
        try "initial".write(
            to: root.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8)
        _ = try runner.run(["add", "."], in: root)
        _ = try runner.run(["commit", "-m", "initial"], in: root)
        return root
    }

    @Test("parses a real repo's branch, modification, untracked and ignored state")
    func realRepo() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = SystemGitRunner()

        // Modify a tracked file, add an untracked one, and ignore a third.
        try "changed".write(
            to: root.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8)
        try "new".write(
            to: root.appendingPathComponent("fresh.txt"),
            atomically: true, encoding: .utf8)
        try "*.log\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true, encoding: .utf8)
        try "noise".write(
            to: root.appendingPathComponent("debug.log"),
            atomically: true, encoding: .utf8)

        let output = try runner.run(
            ["status", "--porcelain=v2", "--branch", "--ignored=matching"], in: root)
        let status = parsePorcelainV2(output, root: root)

        #expect(status.branch == "main")
        #expect(status.entries["tracked.txt"] == .modified)
        #expect(status.entries["fresh.txt"] == .untracked)
        #expect(status.entries["debug.log"] == .ignored)
    }

    @Test("distinguishes staged from unstaged against real git")
    func realStaging() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = SystemGitRunner()

        try "staged change".write(
            to: root.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8)
        _ = try runner.run(["add", "tracked.txt"], in: root)

        let output = try runner.run(["status", "--porcelain=v2", "--branch"], in: root)
        let status = parsePorcelainV2(output, root: root)
        #expect(status.entries["tracked.txt"] == .staged)
    }

    @Test("parses a real rename, keying by the new path")
    func realRename() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = SystemGitRunner()

        _ = try runner.run(["mv", "tracked.txt", "renamed.txt"], in: root)

        let output = try runner.run(["status", "--porcelain=v2", "--branch"], in: root)
        let status = parsePorcelainV2(output, root: root)
        #expect(status.entries["renamed.txt"] == .renamed)
        // The OLD path must not leak in as its own entry.
        #expect(status.entries["tracked.txt"] == nil)
    }

    @Test("the provider resolves and caches a real repo end to end")
    func realProvider() async throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try "changed".write(
            to: root.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8)

        let provider = GitStatusProvider(fileSystem: LocalFileSystemService())
        await provider.refreshIfNeeded(directory: root)

        #expect(provider.status(forDirectory: root)?.branch == "main")
        #expect(provider.status(for: root.appendingPathComponent("tracked.txt")) == .modified)
    }

    @Test("a directory outside any repo yields no status")
    func realNonRepo() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = GitStatusProvider(fileSystem: LocalFileSystemService())
        await provider.refreshIfNeeded(directory: root)
        #expect(provider.status(forDirectory: root) == nil)
    }
}
