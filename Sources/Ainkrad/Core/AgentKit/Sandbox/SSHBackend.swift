// Sources/Ainkrad/Core/AgentKit/Sandbox/SSHBackend.swift
import Foundation

/// Runs on a remote host over SSH. No local isolation — the remote host is the
/// boundary.
///
/// ## Per-request targeting
///
/// This used to hold one fixed `SSHConnectionInfo?`, wired `nil` everywhere
/// because there was no host-side connection bridge. There is one now
/// (`leyline.resolve_connection`), so the target is resolved **per call**
/// instead: `ExecutionRequest.remote` names a saved connection and
/// `resolveConnection` turns it into an `SSHConnectionInfo`. There is
/// deliberately no hidden "active remote" — the caller names its target every
/// time, so a command can never land on a machine the user didn't just name.
///
/// ## FAIL-CLOSED — the invariant this file exists to protect
///
/// Matching `DockerBackend`/`SeatbeltBackend`: there is NO path where a remote
/// command falls through to running unsandboxed on the LOCAL host. Every way of
/// not having a remote to run on throws `BackendError.unavailable` *before*
/// anything is spawned:
///
/// - no resolver wired at all (nothing can answer),
/// - no `remote` named on the request,
/// - the resolver failing for any reason — Leyline absent, unknown id,
///   password-only connection, passphrase-protected key.
///
/// Only a fully resolved connection reaches the `ssh` spawn, and that spawn's
/// own failure is surfaced in the result (never silently swallowed into a local
/// re-run). `SSHBackendTests` pins each of those paths with a marker file the
/// never-run command would have created locally.
struct SSHBackend: ExecutionBackend {
    let kind: SandboxBackendKind = .ssh
    var runner = SandboxProcessRunner()
    var sshPath = "/usr/bin/ssh"
    /// Resolves `ExecutionRequest.remote` into a connection. `nil` means no
    /// provider is wired at all, which is itself fail-closed: `run` throws.
    let resolveConnection: SSHConnectionResolver?

    init(resolveConnection: SSHConnectionResolver?) {
        self.resolveConnection = resolveConnection
    }

    /// Availability is about this host's ability to *attempt* a remote run: an
    /// `ssh` binary and something that can answer for connection ids. Whether a
    /// particular connection exists is a per-request question, answered in
    /// `run` — resolving it here would need a request we don't have, and would
    /// also mean a failure surfaced as a generic "backend unavailable" instead
    /// of the specific, actionable reason.
    func isAvailable() async -> Bool {
        resolveConnection != nil && FileManager.default.isExecutableFile(atPath: sshPath)
    }

    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        guard let resolveConnection else {
            throw BackendError.unavailable(
                "No SSH connection provider is wired for this run — blocked, not executed "
                    + "locally. Install the Leyline app to run commands on a saved host.")
        }
        let requested = (request.remote ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else {
            throw BackendError.unavailable(
                "This run targets SSH but names no connection — blocked, not executed "
                    + "locally. Pass the id of a saved Leyline connection.")
        }
        let conn: SSHConnectionInfo
        switch await resolveConnection(requested) {
        case .success(let resolved):
            conn = resolved
        case .failure(let failure):
            // The resolver's reason is already specific (Leyline absent,
            // unknown id, password-only, passphrase-protected); it is prefixed
            // rather than replaced so the user sees the cause AND that nothing
            // ran anywhere.
            throw BackendError.unavailable("Remote command blocked, not executed locally. \(failure.reason)")
        }

        let args = SSHArgsBuilder.args(conn, command: request.command)
        // BatchMode=yes + ConnectTimeout=10 (baked into SSHArgsBuilder) means
        // an unreachable/unauthorized host fails fast with a non-zero exit —
        // never hangs waiting on a password prompt, and never falls through
        // to any local execution path. SandboxProcessRunner's own timeout is
        // a second, independent bound on top of that.
        return await runner.run(
            executable: sshPath, arguments: args,
            workingDir: nil,
            timeout: TimeInterval(request.profile.resourceLimits.timeoutSeconds),
            onOutput: request.onOutput, controller: request.processController)
    }
}
