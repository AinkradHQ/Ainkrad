// Sources/Ainkrad/Core/AgentKit/Sandbox/ExecutionBackend.swift
import Foundation

/// A single request to run a command under a given sandbox profile. The
/// backend (host/seatbelt/docker/ssh) interprets `command` and `profile`
/// into a concrete argv and delegates the actual spawn to `SandboxProcessRunner`.
struct ExecutionRequest: Sendable {
    let command: String  // shell command line (runner wraps with the backend's argv)
    let workingDir: String?
    let profile: SandboxProfile
    /// Optional live-output sink: invoked (on a background queue) with the
    /// cumulative combined stdout+stderr snapshot after each drained chunk. Nil
    /// (the default) is byte-identical to the pre-streaming capture-only path.
    var onOutput: (@Sendable (String) -> Void)? = nil
    /// Optional handle that lets the caller force-kill the live child process
    /// (e.g. on user interrupt) once it's registered by `SandboxProcessRunner.run`.
    var processController: TerminalProcessController? = nil
    /// The id of a saved remote connection to run this command ON, or nil for a
    /// local run. Read only by `SSHBackend`; every other backend ignores it, so
    /// a request without it is byte-identical to the pre-remote path.
    ///
    /// Per-call by design — there is no ambient "active remote" anywhere in the
    /// system, so the caller names its target every time and a command can
    /// never land on a machine nobody just named.
    var remote: String? = nil

    init(
        command: String, workingDir: String?, profile: SandboxProfile,
        onOutput: (@Sendable (String) -> Void)? = nil,
        processController: TerminalProcessController? = nil,
        remote: String? = nil
    ) {
        self.command = command
        self.workingDir = workingDir
        self.profile = profile
        self.onOutput = onOutput
        self.processController = processController
        self.remote = remote
    }
}

/// The fully-captured outcome of one execution. See the streaming open item
/// in the M7 Slice 6 plan — this preserves `RunTerminalTool`'s "capture fully,
/// return once" behavior; no incremental token stream yet.
struct ExecutionResult: Sendable, Equatable {
    let output: String
    let exitCode: Int32
    let timedOut: Bool
    let unresponsive: Bool
    var isError: Bool { timedOut || unresponsive || exitCode != 0 }
}

enum BackendError: Error, Equatable {
    case unavailable(String)  // backend not installed/running — actionable guidance
    case launch(String)  // process failed to launch
    case profileGeneration(String)  // seatbelt SBPL could not be generated/written (fail-closed)
}

/// A pluggable execution isolation backend. `run` returns a fully-captured result
/// (see the streaming open item in the plan). `isAvailable` feature-detects.
protocol ExecutionBackend: Sendable {
    var kind: SandboxBackendKind { get }
    func isAvailable() async -> Bool
    func run(_ request: ExecutionRequest) async throws -> ExecutionResult
}
