// Sources/Ainkrad/Core/AgentKit/Sandbox/Cloud/CloudSandbox.swift
import Foundation

/// Cloud providers a `CloudSandboxBackend` may target. Adding a case here does
/// NOT make cloud runs available — a provider is only usable once its
/// credentials are configured (`CloudCredentialsStore.isConfigured`) AND the
/// Agent's policy explicitly opts in (`ExecutionRouter` / `allowCloud`).
enum CloudProvider: String, Codable, Equatable, Sendable, CaseIterable {
    case modal, daytona, singularity
}

/// Coarse lifecycle of a serverless/cloud sandbox instance. Cloud backends are
/// expected to hibernate on idle and wake on demand rather than staying warm.
enum CloudLifecycleState: Sendable, Equatable {
    case cold
    case waking
    case running
    case hibernating
}

/// A cloud/serverless execution backend — runs commands on a remote sandbox
/// rather than the local host. Refines `ExecutionBackend`; `kind` is always
/// `.cloud`.
///
/// Fail-closed contract (do not weaken):
/// - Cloud is OPT-IN only. With no credentials configured for `provider`,
///   `isAvailable()` MUST return `false` and `run(_:)` MUST return a failed
///   `ExecutionResult` carrying actionable guidance — it must NEVER execute
///   the command locally/unsandboxed or on any other backend as a fallback.
/// - `wake()`/`hibernate()` manage remote lifecycle only; they never cause a
///   command to run outside the remote sandbox.
protocol CloudSandboxBackend: ExecutionBackend {
    var provider: CloudProvider { get }

    /// Transitions the remote sandbox from `.cold`/`.hibernating` toward
    /// `.running`. Must throw (never silently no-op into a running state) if
    /// the provider is not configured or the wake fails.
    func wake() async throws

    /// Transitions the remote sandbox toward `.hibernating`/`.cold` to save
    /// cost. Best-effort — does not throw.
    func hibernate() async
}

/// Stub `CloudSandboxBackend` — establishes the adapter seam and enforces the
/// fail-closed unconfigured path. The concrete remote-exec driver (actually
/// provisioning and running commands on `provider`'s infrastructure) is a
/// LABELED RESEARCH ITEM tracked as a follow-up task: even once credentials
/// ARE configured, this stub still fails closed rather than guessing at a
/// remote protocol. It never falls back to running commands on the local
/// host.
@MainActor
final class StubCloudSandboxBackend: CloudSandboxBackend {
    let kind: SandboxBackendKind = .cloud
    let provider: CloudProvider
    private let credentials: CloudCredentialsStore
    private(set) var lifecycleState: CloudLifecycleState = .cold

    init(provider: CloudProvider, credentials: CloudCredentialsStore) {
        self.provider = provider
        self.credentials = credentials
    }

    /// Fail-closed: unavailable whenever no credentials are configured for
    /// `provider`. This is the ONLY signal `ExecutionRouter` uses to decide
    /// whether to route to this backend — see `ExecutionRouter.route`.
    func isAvailable() async -> Bool {
        credentials.isConfigured(provider)
    }

    func wake() async throws {
        guard credentials.isConfigured(provider) else {
            throw BackendError.unavailable(
                "Cloud provider \(provider.rawValue) is not configured — add credentials before waking a cloud sandbox."
            )
        }
        // RESEARCH ITEM (follow-up task): the actual remote-provisioning call
        // for `provider` is not implemented. Fail closed rather than
        // pretending the remote sandbox woke up.
        throw BackendError.unavailable(
            "Cloud provider \(provider.rawValue) remote wake is not yet implemented.")
    }

    func hibernate() async {
        lifecycleState = .hibernating
        lifecycleState = .cold
    }

    /// Fail-closed `run`: with no credentials configured, returns a failed
    /// result with guidance and NEVER runs the command anywhere. Even when
    /// credentials ARE configured, the remote-exec driver is a RESEARCH ITEM
    /// (follow-up task) — this stub still fails closed rather than executing
    /// locally.
    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        guard credentials.isConfigured(provider) else {
            return ExecutionResult(
                output:
                    "Cloud provider \(provider.rawValue) is not configured. Add credentials before running commands in the cloud sandbox. The command was not run.",
                exitCode: 1,
                timedOut: false,
                unresponsive: false)
        }
        return ExecutionResult(
            output:
                "Cloud execution for provider \(provider.rawValue) is not yet implemented. The command was not run.",
            exitCode: 1,
            timedOut: false,
            unresponsive: false)
    }
}
