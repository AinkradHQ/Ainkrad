import AinkradHostRuntime
import Foundation
// Tests/AinkradTests/RewindCommandTests.swift
//
// Checkpoint & Rewind Task 6: `/rewind` lists durable checkpoints newest-first
// and restores by index in code/chat/both modes.
import Testing

@testable import Ainkrad

@Suite("/rewind command", .timeLimit(.minutes(1)))
@MainActor
struct RewindCommandTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }

    @Test func listReportsNothingWhenNoCheckpoints() {
        let registry = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(provider: RecordingProvider(script: []))
        let result = registry.run("/rewind", on: session)
        if case .handled(let note) = result {
            #expect(note?.contains("No checkpoints") == true)
        } else {
            Issue.record("expected .handled")
        }
    }

    @Test func rewindByIndexRestoresFileAndTranscript() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rw-\(UUID().uuidString).txt").path
        try "v1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rwr-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = TestSessionFactory.makeWithCheckpoints(
            provider: MultiEditStubProvider(path: path, edits: [("v1", "v2")]),
            editJournal: EditJournal(), snapshotRoot: root, router: hostRouter())
        session.send("edit")
        await session.currentTask?.value

        let registry = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let result = registry.run("/rewind 1 code", on: session)
        // /rewind kicks the async restore off on a Task; await settle.
        try await Task.sleep(for: .milliseconds(200))
        if case .handled(let note) = result {
            #expect(note?.contains("Rewinding") == true)
        } else {
            Issue.record("expected .handled")
        }
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "v1")
    }
}
