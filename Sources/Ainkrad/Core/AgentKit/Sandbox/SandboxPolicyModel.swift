import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Segmented-picker-friendly stand-in for `NetworkPolicy`'s associated-value
/// case (`AinkradSegmentedPicker` needs a plain `Hashable` selection). The
/// allow-list hosts themselves are edited separately, only when `.allowList`
/// is selected.
enum NetworkMode: String, CaseIterable, Hashable, Sendable {
    case off, allowList, on

    var title: String {
        switch self {
        case .off: return "Off"
        case .allowList: return "Allow-list"
        case .on: return "On"
        }
    }
}

/// `NetworkPolicy` <-> `NetworkMode` conversions. Pure, unit-testable without
/// a view — the allow-list hosts are carried separately so switching modes
/// back and forth never silently drops a previously-typed host list.
enum NetworkModeMapping {
    static func mode(for policy: NetworkPolicy) -> NetworkMode {
        switch policy {
        case .off: return .off
        case .on: return .on
        case .allowList: return .allowList
        }
    }

    static func policy(for mode: NetworkMode, hosts: [String]) -> NetworkPolicy {
        switch mode {
        case .off: return .off
        case .on: return .on
        case .allowList: return .allowList(hosts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}

/// Drives the "why was this blocked/allowed" inspector: picks a sample tool's
/// permission class (mirroring the real `AgentTool.permission` values) and
/// runs the SAME two-step pipeline the runtime uses (`AgentPermissionPolicy`
/// gate, then `SandboxPermissionPolicy.compose`) so the explanation shown
/// here can never drift from what the tool call would actually do. Pure, no
/// I/O — unit-testable without a view or a store.
enum SandboxPolicyExplainer {
    /// Illustrative subset of real tool names (`AgentTool.name` values) — not
    /// an exhaustive registry lookup, since this pane is a fail-closed
    /// explainer, not a live tool catalog.
    static let sampleToolNames = ["read_file", "edit_file", "run_terminal", "mcp/gitmage/push", "workspace_control"]

    static func permissionClass(for toolName: String) -> ToolPermissionClass {
        toolName == "read_file" ? .read : .write
    }

    static func explain(
        profile: SandboxProfile,
        toolName: String,
        mode: AgentPermissionMode,
        allowlist: Set<String>,
        gateReads: Bool
    ) -> PermissionExplanation {
        let gate = AgentPermissionPolicy.decide(
            toolPermission: permissionClass(for: toolName),
            toolName: toolName,
            mode: mode,
            allowlist: allowlist,
            gateReads: gateReads,
            isIrreversible: false)
        return SandboxPermissionPolicy.compose(
            gate: gate,
            agentAllowList: nil,   // this inspector explains the SANDBOX layer; no per-Agent restriction assumed
            sandboxAllowList: profile.toolAllowList,
            toolName: toolName)
    }
}

/// Factory for a brand-new user-defined profile — fail-closed defaults
/// (network off, no fs access granted, `allowHostOverride` false) so a fresh
/// profile never accidentally grants more than the user explicitly adds.
enum SandboxProfileFactory {
    static func blank() -> SandboxProfile {
        SandboxProfile(
            id: UUID().uuidString,
            name: "New profile",
            backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .off,
            resourceLimits: ResourceLimits(timeoutSeconds: 60),
            toolAllowList: [],
            allowHostOverride: false)
    }
}
