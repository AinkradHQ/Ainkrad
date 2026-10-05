// Sources/Ainkrad/Core/AgentKit/Sandbox/DockerBackend.swift
import Foundation

/// Runs inside a container via `docker run`. Feature-detected: if the `docker`
/// CLI can't be resolved, or the daemon doesn't respond to `docker info`
/// within a bounded timeout, the backend is unavailable. FAIL-CLOSED
/// invariant, matching `SeatbeltBackend`: there is NO path where an
/// unavailable Docker falls through to running the command unsandboxed on
/// the host — `run` throws `.unavailable` with actionable guidance instead.
struct DockerBackend: ExecutionBackend {
    let kind: SandboxBackendKind = .docker
    var runner = SandboxProcessRunner()
    var dockerPath = "/usr/local/bin/docker"
    /// Extra binary locations (Docker Desktop / colima / Homebrew ARM prefix).
    /// Tests inject `[]` (together with a nonexistent `dockerPath`) to force
    /// the unavailable branch deterministically, even on a dev box that has
    /// Docker installed — resolution then provably fails without touching
    /// any real Docker install, so this never spawns a container in `make test`.
    var fallbackPaths: [String] = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker"]
    /// confirm at execution: base image strategy (fixed vs. user-specified)
    /// is an open item — kept injectable so a future profile field can drive it.
    var image = "ainkrad/exec:latest"

    /// Feature detection: resolves the binary (a stat check, not a spawn),
    /// then confirms the daemon actually responds via `docker info` — but
    /// bounded by `SandboxProcessRunner`'s timeout, so a hung/unresponsive
    /// Docker daemon can't hang this check or the caller.
    func isAvailable() async -> Bool {
        guard let resolved = resolveDocker() else { return false }
        let result = await runner.run(
            executable: resolved, arguments: ["info"],
            workingDir: nil, timeout: 8)
        return !result.timedOut && !result.unresponsive && result.exitCode == 0
    }

    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        // Fail-closed: unresolvable binary or unresponsive/absent daemon
        // blocks the command outright — never silently runs on the host.
        guard let resolved = resolveDocker(), await isAvailable() else {
            throw BackendError.unavailable(
                "Docker isn't available (CLI not found or daemon not running). "
                    + "Install/start Docker Desktop (or colima), or choose a seatbelt "
                    + "profile instead — this run was blocked, not executed on the host.")
        }

        let workspace = request.workingDir ?? NSHomeDirectory()
        let args = DockerArgsBuilder.runArgs(
            command: request.command, profile: request.profile,
            workspacePath: workspace, image: image)
        return await runner.run(
            executable: resolved,
            arguments: args,
            workingDir: workspace,
            timeout: TimeInterval(request.profile.resourceLimits.timeoutSeconds),
            onOutput: request.onOutput, controller: request.processController)
    }

    /// Resolves the docker binary: `dockerPath` if executable, else the first
    /// executable entry in `fallbackPaths`. Both are injectable so tests can
    /// force resolution to fail deterministically without touching a real
    /// Docker install (see `fallbackPaths` doc above).
    private func resolveDocker() -> String? {
        if FileManager.default.isExecutableFile(atPath: dockerPath) { return dockerPath }
        return fallbackPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
