import Foundation
import Testing

@testable import Ainkrad

@Suite("Rewind affordance model")
struct RewindAffordanceTests {
    @Test func mapsCheckpointsToRowsNewestFirst() {
        let now = Date()
        let cps = [
            Checkpoint(
                id: UUID(), sessionID: "s", createdAt: now, label: "Before: build",
                toolName: "run_terminal", transcriptIndex: 4, fileSnapshots: [], gitStashSHA: "sha", gitRepoRoot: "/r"),
            Checkpoint(
                id: UUID(), sessionID: "s", createdAt: now.addingTimeInterval(-10), label: "Before edit a.txt",
                toolName: "edit_file", transcriptIndex: 2,
                fileSnapshots: [FileSnapshot(path: "a.txt", existedBefore: true, blobName: "blob-1")],
                gitStashSHA: nil, gitRepoRoot: nil),
            Checkpoint(
                id: UUID(), sessionID: "s", createdAt: now.addingTimeInterval(-20), label: "Before: chat only",
                toolName: "run_terminal", transcriptIndex: 1, fileSnapshots: [], gitStashSHA: nil, gitRepoRoot: nil),
        ]
        let rows = RewindMenuModel.rows(from: cps)
        #expect(rows.count == 3)
        #expect(rows.first?.title == "Before: build")
        #expect(rows.first?.canRestoreCode == true)  // has a git stash
        #expect(rows[1].canRestoreCode == true)  // edit_file file snapshot
        #expect(rows.last?.title == "Before: chat only")
        #expect(rows.last?.canRestoreCode == false)  // no file snapshot AND no git stash
    }
}
