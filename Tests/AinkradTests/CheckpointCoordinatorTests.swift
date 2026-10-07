import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("CheckpointCoordinator", .timeLimit(.minutes(1)))
@MainActor
struct CheckpointCoordinatorTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test func capturesFileSnapshotBeforeAnEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("e-\(UUID().uuidString).txt")
        try "before".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        var index = 5
        let coord = CheckpointCoordinator(
            sessionID: "s1", snapshots: WorkspaceSnapshotStore(root: root),
            git: GitWorkingTreeSnapshotter(router: hostRouter()),
            persistence: InMemoryPersistenceStore(),
            transcriptIndex: { index }, defaultWorkingDir: NSHomeDirectory())

        let call = ToolCall(id: "1", name: "edit_file", input: obj(["path": .string(file.path)]))
        await coord.captureIfMutating(call: call, tool: EditFileTool())
        #expect(coord.checkpoints().count == 1)
        #expect(coord.checkpoints().first?.transcriptIndex == 5)
        #expect(coord.checkpoints().first?.fileSnapshots.first?.path == file.path)

        // Mutate the file, then restore code-only.
        try "after".write(to: file, atomically: true, encoding: .utf8)
        let outcome = await coord.restore(coord.checkpoints()[0], mode: .code)
        #expect(outcome.transcriptIndex == -1)
        #expect(outcome.success == true)
        #expect((try? String(contentsOf: file, encoding: .utf8)) == "before")
    }

    @Test func ignoresReadClassTools() async {
        let coord = CheckpointCoordinator(
            sessionID: "s", snapshots: WorkspaceSnapshotStore(root: FileManager.default.temporaryDirectory),
            git: GitWorkingTreeSnapshotter(router: hostRouter()),
            persistence: InMemoryPersistenceStore(), transcriptIndex: { 0 }, defaultWorkingDir: NSHomeDirectory())
        await coord.captureIfMutating(
            call: ToolCall(id: "1", name: "read_file", input: .object([:])), tool: ReadFileTool())
        #expect(coord.checkpoints().isEmpty)
    }

    @Test func conversationModeReturnsTranscriptIndex() async {
        let coord = CheckpointCoordinator(
            sessionID: "s",
            snapshots: WorkspaceSnapshotStore(
                root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            git: GitWorkingTreeSnapshotter(router: hostRouter()),
            persistence: InMemoryPersistenceStore(), transcriptIndex: { 7 }, defaultWorkingDir: NSHomeDirectory())
        await coord.captureIfMutating(
            call: ToolCall(id: "1", name: "run_terminal", input: .object(["command": .string("echo hi")])),
            tool: RunTerminalTool(actionHub: AgentActionRegistryHub(), router: hostRouter()))
        let cp = try? #require(coord.checkpoints().first)
        let outcome = await coord.restore(cp!, mode: .conversation)
        #expect(outcome.transcriptIndex == 7)
        #expect(outcome.success == true)
    }
}
