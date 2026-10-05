import Foundation

/// Captures a `run_terminal` mutating command's pre-run working tree as a durable
/// git object via `git stash create` (which writes a commit into the repo's object
/// store WITHOUT touching the index/worktree), so a rewind can `git stash apply`
/// it later — even after untracked-safe changes. Returns nil when `workingDir` is
/// not inside a git repo: that run boundary honestly cannot be rewound past.
/// Runs git through the SAME `ExecutionRouter`/`HostBackend` path `run_terminal`
/// uses (`.mainInteractive`), never a raw unsandboxed spawn.
@MainActor
final class GitWorkingTreeSnapshotter {
    private let router: ExecutionRouter
    init(router: ExecutionRouter) { self.router = router }

    private func run(_ command: String, in dir: String) async -> ExecutionResult? {
        guard let (backend, profile) = try? await router.route(tier: .mainInteractive, policy: nil) else { return nil }
        return try? await backend.run(ExecutionRequest(command: command, workingDir: dir, profile: profile))
    }

    func snapshot(workingDir: String) async -> (repoRoot: String, sha: String)? {
        guard let rootResult = await run("git rev-parse --show-toplevel", in: workingDir),
            !rootResult.isError
        else { return nil }
        let repoRoot = rootResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoRoot.isEmpty else { return nil }
        // `git stash create` prints a commit SHA for the current changes, or nothing
        // when the tree is clean (nothing to snapshot — still a valid checkpoint,
        // signalled by an empty sha the restore path treats as a no-op).
        guard let stash = await run("git stash create", in: repoRoot), !stash.isError else { return nil }
        let sha = stash.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (repoRoot, sha)
    }

    @discardableResult
    func restore(repoRoot: String, sha: String) async -> Bool {
        guard !sha.isEmpty else { return true }  // clean tree at capture time — nothing to apply
        // Defense-in-depth: only interpolate values that look like a git object hash.
        guard sha.allSatisfy({ $0.isHexDigit }) && (7...64).contains(sha.count) else { return false }
        guard let checkout = await run("git checkout -- .", in: repoRoot), !checkout.isError else { return false }
        guard let apply = await run("git stash apply \(sha)", in: repoRoot) else { return false }
        return !apply.isError
    }
}
