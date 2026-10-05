// Sources/Ainkrad/Core/AgentKit/Sandbox/TrustTier.swift
import Foundation

/// Trust tier of a given run — drives the default sandbox policy. Only
/// `.mainInteractive` is ever eligible to route to `HostBackend`; every other
/// tier is sandboxed by default and requires an explicit, persisted opt-in
/// (`SandboxProfile.allowHostOverride`) to ever touch `.host` (see
/// `ExecutionRouter`).
enum TrustTier: String, Codable, Equatable, Sendable, CaseIterable {
    case mainInteractive  // the user's foreground session → host
    case background  // fire-and-forget host-app run → sandboxed
    case scheduled  // cron/scheduled run → sandboxed
    case subagent  // spawned subagent → sandboxed
    case untrustedMCP  // untrusted MCP stdio server → sandboxed
}

/// The per-Agent execution policy the router consumes. Slice 5's
/// `AgentProfile.toolPolicy` (provided by Slice 5) projects into this; where
/// Slice 5 hasn't landed, callers pass `nil` and the router falls back to
/// trust-tier defaults (the restrictive mapping — no escalation).
struct AgentExecutionPolicy: Sendable, Equatable {
    /// Explicit `SandboxProfile.id` this Agent wants to run under. If the id
    /// doesn't resolve (unknown/deleted profile) the router falls back to the
    /// tier's restrictive default rather than erroring or escalating.
    var sandboxProfileID: String?
    /// Per-Agent, explicit opt-in required before a `.cloud` profile may be
    /// selected. A tier alone NEVER implies cloud — this flag is the only path.
    var allowCloud: Bool
    var toolAllowList: Set<String>?
}
