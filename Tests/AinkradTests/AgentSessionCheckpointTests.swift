import AinkradHostRuntime
import Foundation
// Tests/AinkradTests/AgentSessionCheckpointTests.swift
//
// Checkpoint & Rewind Task 5: proves the pre-tool interception point in
// `AgentSession.execute(_:)` captures a durable checkpoint before a mutating
// `edit_file` call runs, and that `restoreCheckpoint(_:mode:)` rewinds both the
// on-disk file and the transcript back to the checkpoint's turn boundary.
import Testing

@testable import Ainkrad

@Suite("AgentSession checkpoints", .timeLimit(.minutes(1)))
@MainActor
struct AgentSessionCheckpointTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }

    @Test func editCapturesACheckpointAndRestoreRewindsFileAndTranscript() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("cp-\(UUID().uuidString).txt").path
        try "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let journal = EditJournal()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cpr-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TestSessionFactory.makeWithCheckpoints(
            provider: MultiEditStubProvider(path: path, edits: [("v1", "v2")]),
            editJournal: journal, snapshotRoot: root, router: hostRouter())

        session.send("update the file")
        await session.currentTask?.value
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v2")

        let coord = try #require(session.activeCheckpointer())
        let cp = try #require(coord.checkpoints().first)
        await session.restoreCheckpoint(cp, mode: .both)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v1")
        // `cp.transcriptIndex` is captured at the pre-tool point — right after the
        // assistant message carrying the `tool_use` block, but before its
        // `tool_result`. Truncating there naively would leave a dangling `tool_use`
        // at the end of the transcript, which the next provider `send` rejects
        // (Fix #3 — branch review finding). The restored transcript must instead
        // land on a clean boundary at or before that index.
        #expect(session.messages.count <= cp.transcriptIndex)
        let endsWithDanglingToolUse =
            session.messages.last?.role == .assistant
            && (session.messages.last?.content.contains {
                if case .toolUse = $0 { return true }
                return false
            } ?? false)
        #expect(!endsWithDanglingToolUse)
        #expect(session.messages.last?.text == "update the file")
    }
}
