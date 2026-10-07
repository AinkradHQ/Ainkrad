import AinkradHostRuntime
import Foundation

/// Orchestrates durable rewind points. At the pre-tool interception point in
/// `AgentSession.execute`, `captureIfMutating` snapshots the workspace before a
/// mutating tool runs: `edit_file` → the target file's bytes; `run_terminal` →
/// a git working-tree stash (nil-and-noted when not a repo). Restores as
/// code-only / conversation-only / both. Cross-session: the index is persisted
/// via `CheckpointIndexDocument`; blobs live under `WorkspaceSnapshotStore`'s
/// app-support root.
@MainActor
final class CheckpointCoordinator {
    enum RestoreMode: Equatable { case code, conversation, both }

    /// `restore(_:mode:)`'s result: the transcript index the caller should truncate
    /// to (`-1` for `.code`, unchanged), AND whether the workspace-restore step
    /// actually succeeded. `success` is `true` unless a git stash restore reported
    /// failure — file-snapshot restore (`WorkspaceSnapshotStore.restore`) is
    /// best-effort/void and doesn't factor in, matching pre-Fix-#1 behavior for the
    /// (far more common) file-only case.
    struct RestoreOutcome: Equatable {
        let transcriptIndex: Int
        let success: Bool
    }

    private let sessionID: String
    private let snapshots: WorkspaceSnapshotStore
    private let git: GitWorkingTreeSnapshotter
    private let persistence: PersistenceStore
    private let transcriptIndex: @MainActor () -> Int
    private let defaultWorkingDir: String
    private var index: [Checkpoint]

    /// Tools whose calls mutate the workspace and thus warrant a checkpoint.
    private static let mutatingTools: Set<String> = ["edit_file", "run_terminal"]

    init(
        sessionID: String, snapshots: WorkspaceSnapshotStore, git: GitWorkingTreeSnapshotter,
        persistence: PersistenceStore, transcriptIndex: @escaping @MainActor () -> Int,
        defaultWorkingDir: String
    ) {
        self.sessionID = sessionID
        self.snapshots = snapshots
        self.git = git
        self.persistence = persistence
        self.transcriptIndex = transcriptIndex
        self.defaultWorkingDir = defaultWorkingDir
        self.index = persistence.load(CheckpointIndexDocument.self)?.checkpoints ?? []
    }

    func checkpoints() -> [Checkpoint] {
        index.filter { $0.sessionID == sessionID }.sorted { $0.createdAt > $1.createdAt }
    }

    func captureIfMutating(call: ToolCall, tool: any AgentTool) async {
        guard tool.permission == .write, Self.mutatingTools.contains(call.name) else { return }
        let id = UUID()
        var fileSnapshots: [FileSnapshot] = []
        var gitSHA: String?
        var repoRoot: String?
        var label = call.name

        if call.name == "edit_file", let path = call.input["path"]?.stringValue, !path.isEmpty {
            fileSnapshots = [snapshots.snapshotFile(path, into: id)]
            label = "Before edit \((path as NSString).lastPathComponent)"
        } else if call.name == "run_terminal" {
            let dir = call.input["working_dir"]?.stringValue ?? defaultWorkingDir
            if let snap = await git.snapshot(workingDir: dir) {
                repoRoot = snap.repoRoot
                gitSHA = snap.sha
            }
            let cmd = call.input["command"]?.stringValue ?? ""
            label = "Before: \(cmd.prefix(48))"
        }

        let checkpoint = Checkpoint(
            id: id, sessionID: sessionID, createdAt: Date(), label: label,
            toolName: call.name, transcriptIndex: transcriptIndex(),
            fileSnapshots: fileSnapshots, gitStashSHA: gitSHA, gitRepoRoot: repoRoot)
        index.append(checkpoint)
        persistence.save(CheckpointIndexDocument(checkpoints: index))
    }

    /// Restores workspace state and/or reports the transcript truncation point.
    /// `transcriptIndex` is the index to truncate to for `.conversation`/`.both`,
    /// or `-1` for `.code` (caller leaves the transcript untouched). `success` is
    /// `false` when a git stash restore was attempted and reported failure — see
    /// `RestoreOutcome`.
    @discardableResult
    func restore(_ checkpoint: Checkpoint, mode: RestoreMode) async -> RestoreOutcome {
        var success = true
        if mode != .conversation {
            for snap in checkpoint.fileSnapshots { snapshots.restore(snap, from: checkpoint.id) }
            if let root = checkpoint.gitRepoRoot, let sha = checkpoint.gitStashSHA {
                success = await git.restore(repoRoot: root, sha: sha)
            }
        }
        return RestoreOutcome(transcriptIndex: mode == .code ? -1 : checkpoint.transcriptIndex, success: success)
    }
}
