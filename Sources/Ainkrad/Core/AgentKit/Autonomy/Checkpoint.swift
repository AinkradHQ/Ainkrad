import AinkradHostRuntime
import Foundation

/// One file's pre-mutation bytes, captured before an `edit_file`. `blobName` is
/// the file name (under the checkpoint's directory) holding the original bytes;
/// nil `blobName` + `existedBefore == false` means "the file did not exist, so
/// restore deletes it".
struct FileSnapshot: Codable, Equatable, Sendable {
    let path: String
    let existedBefore: Bool
    let blobName: String?
}

/// A durable, cross-session rewind point captured at the pre-tool interception
/// point before a mutating tool call. `fileSnapshots` backs `edit_file`;
/// `gitStashSHA`/`gitRepoRoot` back a `run_terminal` git working-tree snapshot
/// (nil when the working dir is not a git repo — that boundary cannot be rewound
/// past, reported honestly to the user).
struct Checkpoint: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sessionID: String
    let createdAt: Date
    let label: String
    let toolName: String
    /// `AgentSession.messages.count` at capture time — restore-conversation
    /// truncates the transcript back to this index.
    let transcriptIndex: Int
    let fileSnapshots: [FileSnapshot]
    let gitStashSHA: String?
    let gitRepoRoot: String?
}

struct CheckpointIndexDocument: PersistableDocument {
    static let documentID = "agent-checkpoints"
    var checkpoints: [Checkpoint]
}
