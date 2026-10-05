// Sources/Ainkrad/Core/AgentKit/Sandbox/Cloud/ModalCloudBackend.swift
import Foundation

/// Modal.com serverless sandbox backend. Bring-your-own-account: requires a
/// Modal token in the Keychain (via `CloudCredentialsStore`). Hibernate-on-idle
/// / wake-on-demand via `CloudLifecycleState`.
///
/// The actual remote-execution call is an injected driver (`remoteExec`) —
/// Modal exposes arbitrary command execution through its Sandboxes API
/// (Python SDK / REST), NOT a documented shell-exec CLI, so hard-coding a
/// protocol here would be guessing. Picking and landing that driver is a 6b
/// research deliverable (see the OPEN ITEM in the Slice 6 plan). Until it
/// lands, the production default driver throws `.unavailable` — this backend
/// NEVER pretends a remote run succeeded and NEVER falls back to running the
/// command on the local host, configured or not.
@MainActor
final class ModalCloudBackend: CloudSandboxBackend {
    /// Executes `request` remotely using `token` and returns its result.
    /// The production default (below) fails closed; only a test double or a
    /// future researched driver may satisfy this.
    typealias RemoteExec = (ExecutionRequest, _ token: String) async throws -> ExecutionResult

    let kind: SandboxBackendKind = .cloud
    let provider: CloudProvider = .modal
    private let credentials: CloudCredentialsStore
    private(set) var state: CloudLifecycleState = .cold

    /// The remote-execution driver. Production default fails closed until the
    /// researched Modal Sandboxes driver lands; tests inject a fake.
    var remoteExec: RemoteExec = { _, _ in
        throw BackendError.unavailable(
            "Modal remote execution driver not implemented yet — run blocked (6b research item; never falls back to host)."
        )
    }

    init(credentials: CloudCredentialsStore) {
        self.credentials = credentials
    }

    /// Fail-closed: only "available" when a Modal token is configured.
    /// Configuration alone does not guarantee a run will succeed — the
    /// default `remoteExec` still blocks until the researched driver lands —
    /// but callers use this signal (e.g. `ExecutionRouter`) to decide whether
    /// to even attempt routing here.
    func isAvailable() async -> Bool {
        credentials.isConfigured(.modal)
    }

    /// Transitions toward `.running`. Throws (never silently no-ops) if
    /// Modal isn't configured.
    func wake() async throws {
        guard await isAvailable() else {
            throw BackendError.unavailable(
                "Modal isn't configured. Add your Modal token in Settings ▸ Sandboxing ▸ Cloud — this run was blocked.")
        }
        state = .waking
        // The researched driver owns the real warm/create call against
        // Modal's Sandboxes API; lifecycle state is tracked here so Slice 3's
        // Runs monitor can surface it regardless of which driver lands.
        state = .running
    }

    /// Best-effort — never throws.
    func hibernate() async {
        state = .hibernating
    }

    /// Fail-closed `run`: unconfigured, OR configured but the remote-exec
    /// driver is not yet implemented, both block here — never local, never a
    /// claimed success.
    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        guard await isAvailable(), let token = credentials.credential(for: .modal) else {
            throw BackendError.unavailable(
                "Modal isn't configured — run blocked (never falls back to host).")
        }
        if state != .running {
            try await wake()
        }
        let result = try await remoteExec(request, token)
        // Hibernate-on-idle: drop back after a run completes so the sandbox
        // isn't left billing while idle.
        await hibernate()
        return result
    }
}
