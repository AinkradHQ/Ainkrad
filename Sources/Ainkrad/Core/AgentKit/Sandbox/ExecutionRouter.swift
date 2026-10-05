// Sources/Ainkrad/Core/AgentKit/Sandbox/ExecutionRouter.swift
import Foundation

enum ExecutionRouterError: Error, Equatable {
    /// The resolved backend's `isAvailable()` returned false, or no backend was
    /// registered for the resolved profile's `SandboxBackendKind`. NEVER
    /// substituted with host — the run is blocked.
    case backendUnavailable(SandboxBackendKind, String)
    /// The resolved profile targets `.cloud` but the Agent's policy did not
    /// explicitly set `allowCloud == true`. A tier alone never yields cloud.
    case cloudNotOptedIn
}

/// Chooses the backend + profile for a run from its trust tier + Agent policy.
///
/// Fail-closed invariants (do not weaken):
/// - `HostBackend` is reachable ONLY for `.mainInteractive`. Every other tier
///   resolves to a sandboxed profile; a policy naming a `.host` profile for a
///   non-main tier is downgraded to the restrictive default unless the named
///   profile explicitly sets `allowHostOverride == true` (persisted opt-in,
///   never a default).
/// - An unknown/unresolvable `sandboxProfileID` falls back to the tier's
///   restrictive default — never an error that could be mishandled upstream,
///   never escalation.
/// - `.cloud` requires `policy.allowCloud == true`; otherwise throws.
/// - A `remote` on `route` forces `.ssh` and can never resolve to any other
///   backend — in particular a remote run never silently becomes a local one.
/// - If the resolved backend is unavailable (or unregistered), `route` throws
///   `.backendUnavailable` — it never substitutes a different (more
///   permissive) backend, and never falls back to host.
@MainActor
final class ExecutionRouter {
    private let profiles: SandboxProfileStore
    private let backends: [SandboxBackendKind: any ExecutionBackend]

    init(profiles: SandboxProfileStore, backends: [SandboxBackendKind: any ExecutionBackend]) {
        self.profiles = profiles
        self.backends = backends
    }

    /// Resolves the `SandboxProfile` for a (tier, policy) pair, applying the
    /// no-silent-escalation guard. Pure/synchronous — does not check backend
    /// availability (that happens in `route`).
    func resolveProfile(tier: TrustTier, policy: AgentExecutionPolicy?) -> SandboxProfile {
        let workspaceWrite =
            profiles.profile(id: BuiltInSandboxProfiles.defaultNonMainID)
            ?? BuiltInSandboxProfiles.workspaceWrite

        // Explicit per-Agent profile takes precedence when it resolves to a
        // known profile. An unknown id is NOT an error here — it falls back
        // to the tier's restrictive default (fail-closed, never a crash and
        // never an implicit escalation).
        if let id = policy?.sandboxProfileID, let p = profiles.profile(id: id) {
            // No silent escalation: a non-main tier may only use a `.host`
            // profile when that profile explicitly opted in.
            if p.backend == .host && tier != .mainInteractive && !p.allowHostOverride {
                return workspaceWrite
            }
            // Narrowing CEILING (defense-in-depth): for `.background` runs, a
            // posture-named *sandboxed* profile (anything other than `.host`,
            // which is already gated above, and `.cloud`, which is gated by
            // `allowCloud` in `route`) must not be MORE permissive than the
            // tier's own restrictive default. This mirrors the permission-mode
            // narrowing philosophy elsewhere: a schedule/trigger posture can
            // only make a background run more restrictive (or equal), never
            // broader than `workspace-write`. Not a live vuln today (nothing
            // currently writes a broader posture), but closes the ceiling so
            // a future posture author can't silently widen a background run.
            if tier == .background && p.backend != .host && p.backend != .cloud
                && !p.isNoMorePermissive(than: workspaceWrite)
            {
                return workspaceWrite
            }
            return p
        }

        switch tier {
        case .mainInteractive:
            return profiles.profile(id: BuiltInSandboxProfiles.mainID) ?? BuiltInSandboxProfiles.hostTrusted
        case .background, .scheduled, .subagent, .untrustedMCP:
            return workspaceWrite
        }
    }

    /// Resolves the backend + profile and verifies the backend is actually
    /// available. Fail-closed: unavailable/unregistered backends throw rather
    /// than falling back to a more permissive backend (host in particular).
    ///
    /// `remote` names a saved SSH connection. When present the run goes to the
    /// `.ssh` backend **regardless of tier or the profile's own `backend`** —
    /// the profile is still resolved and returned, because its resource limits
    /// and timeout still bound the run. This is not an escalation: `.ssh` is
    /// the one backend that executes nothing on this machine, so overriding
    /// *into* it can only move a command further away from local authority, and
    /// `SSHBackend` refuses to run at all unless the id resolves.
    ///
    /// Omitting `remote` (the default) leaves every existing caller on exactly
    /// the path it had before.
    func route(tier: TrustTier, policy: AgentExecutionPolicy?, remote: String? = nil) async throws
        -> (any ExecutionBackend, SandboxProfile)
    {
        let profile = resolveProfile(tier: tier, policy: policy)
        let targetsRemote = !(remote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let kind: SandboxBackendKind = targetsRemote ? .ssh : profile.backend

        // Cloud is opt-in per-Agent, never a tier default. Checked before
        // backend lookup so an unregistered cloud backend never masks a
        // missing opt-in as a generic "unavailable" error.
        if kind == .cloud && policy?.allowCloud != true {
            throw ExecutionRouterError.cloudNotOptedIn
        }
        guard let backend = backends[kind] else {
            throw ExecutionRouterError.backendUnavailable(kind, "No backend registered.")
        }
        guard await backend.isAvailable() else {
            throw ExecutionRouterError.backendUnavailable(
                kind,
                "Backend \(kind.rawValue) is unavailable — run blocked (never falls back to host).")
        }
        return (backend, profile)
    }
}
