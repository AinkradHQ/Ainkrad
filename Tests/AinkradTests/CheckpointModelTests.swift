import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Checkpoint model")
struct CheckpointModelTests {
    @Test func indexRoundTripsThroughPersistence() {
        let store = InMemoryPersistenceStore()
        let snap = FileSnapshot(path: "/tmp/a.txt", existedBefore: true, blobName: "abc.blob")
        let cp = Checkpoint(
            id: UUID(), sessionID: "s1", createdAt: Date(timeIntervalSince1970: 10),
            label: "Before edit a.txt", toolName: "edit_file", transcriptIndex: 3,
            fileSnapshots: [snap], gitStashSHA: nil, gitRepoRoot: nil)
        store.save(CheckpointIndexDocument(checkpoints: [cp]))
        let loaded = store.load(CheckpointIndexDocument.self)
        #expect(loaded?.checkpoints.count == 1)
        #expect(loaded?.checkpoints.first?.label == "Before edit a.txt")
        #expect(loaded?.checkpoints.first?.fileSnapshots.first?.blobName == "abc.blob")
    }

    @Test func documentIDIsStable() {
        #expect(CheckpointIndexDocument.documentID == "agent-checkpoints")
    }
}
