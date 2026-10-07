import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Checkpoint bootstrap wiring", .timeLimit(.minutes(1)))
@MainActor
struct CheckpointBootstrapWiringTests {
    @Test func persistedCheckpointsSurviveANewCoordinatorOverSameStore() {
        let persistence = InMemoryPersistenceStore()
        let cp = Checkpoint(
            id: UUID(), sessionID: "main", createdAt: Date(), label: "Before edit x",
            toolName: "edit_file", transcriptIndex: 1, fileSnapshots: [], gitStashSHA: nil, gitRepoRoot: nil)
        persistence.save(CheckpointIndexDocument(checkpoints: [cp]))

        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: persistence), backends: [.host: HostBackend()])
        let coord = CheckpointCoordinator(
            sessionID: "main",
            snapshots: WorkspaceSnapshotStore(
                root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            git: GitWorkingTreeSnapshotter(router: router), persistence: persistence,
            transcriptIndex: { 0 }, defaultWorkingDir: NSHomeDirectory())
        #expect(coord.checkpoints().count == 1)  // loaded from disk, not lost across sessions
    }
}
