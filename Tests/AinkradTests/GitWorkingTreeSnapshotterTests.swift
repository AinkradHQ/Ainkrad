import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("GitWorkingTreeSnapshotter", .timeLimit(.minutes(1)))
@MainActor
struct GitWorkingTreeSnapshotterTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }

    @Test func snapshotIsNilOutsideAGitRepo() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nogit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = GitWorkingTreeSnapshotter(router: hostRouter())
        let result = await snap.snapshot(workingDir: dir.path)
        #expect(result == nil)
    }

    @Test func snapshotCapturesAndRestoresAWorkingTreeChange() async throws {
        let router = hostRouter()
        let snap = GitWorkingTreeSnapshotter(router: router)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Init a repo with one committed file.
        let host = HostBackend()
        _ = try await host.run(
            ExecutionRequest(
                command:
                    "git init -q && git config user.email t@t && git config user.name t && echo v1 > f.txt && git add -A && git commit -q -m init",
                workingDir: dir.path, profile: BuiltInSandboxProfiles.hostTrusted))

        // Mutate the working tree, snapshot, mutate again, restore.
        _ = try await host.run(
            ExecutionRequest(
                command: "echo v2 > f.txt", workingDir: dir.path, profile: BuiltInSandboxProfiles.hostTrusted))
        let cp = try #require(await snap.snapshot(workingDir: dir.path))
        _ = try await host.run(
            ExecutionRequest(
                command: "echo v3 > f.txt", workingDir: dir.path, profile: BuiltInSandboxProfiles.hostTrusted))
        let restored = await snap.restore(repoRoot: cp.repoRoot, sha: cp.sha)
        #expect(restored)

        let readBack = try await host.run(
            ExecutionRequest(command: "cat f.txt", workingDir: dir.path, profile: BuiltInSandboxProfiles.hostTrusted))
        #expect(readBack.output.contains("v2"))
    }
}
