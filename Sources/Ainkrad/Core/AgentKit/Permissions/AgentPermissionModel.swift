import Foundation

enum AgentPermissionMode: String, Codable, CaseIterable, Sendable {
    case ask, autoApprove, fullAuto

    var glyph: String {
        switch self {
        case .ask: "hand.raised"
        case .autoApprove: "bolt"
        case .fullAuto: "bolt.fill"
        }
    }
}

enum PermissionDecision: Sendable, Equatable { case autoApprove, requireApproval }

enum AgentPermissionPolicy {
    /// Decide whether a pending tool call runs unattended or must hit the HUD.
    /// - Any call the tool marks `isIrreversible` ALWAYS requires approval, in every mode —
    ///   checked first, before the allowlist/mode logic below, so "Allow always" on a tool
    ///   name (which allowlists the whole tool, not a specific invocation) can never bypass
    ///   an irreversible call made later through that same tool. This is also the backstop
    ///   for `isTrusted` below: a trusted MCP server's tool can still never auto-approve an
    ///   irreversible call, since this check runs first and unconditionally.
    /// - `toolPermission == .memory` and `isTrusted` are two independent, composable
    ///   early-return exemptions — both checked after the irreversible guard, in every mode.
    /// - `ask`: reads auto-approve unless `gateReads`; writes always require approval.
    /// - `autoApprove`: allowlisted tools auto-approve; reads auto-approve unless `gateReads`;
    ///   other writes require approval.
    /// - `fullAuto`: everything (writes included) auto-approves, regardless of `gateReads`.
    static func decide(
        toolPermission: ToolPermissionClass,
        toolName: String,
        mode: AgentPermissionMode,
        allowlist: Set<String>,
        gateReads: Bool,
        isIrreversible: Bool,
        isTrusted: Bool = false
    ) -> PermissionDecision {
        if isIrreversible { return .requireApproval }
        if toolPermission == .memory { return .autoApprove }  // memory-only writes are exempt
        if isTrusted { return .autoApprove }  // per-server MCP trust: bounded by isIrreversible above
        switch mode {
        case .fullAuto:
            return .autoApprove
        case .ask:
            return (toolPermission == .read && !gateReads) ? .autoApprove : .requireApproval
        case .autoApprove:
            if allowlist.contains(toolName) { return .autoApprove }
            return (toolPermission == .read && !gateReads) ? .autoApprove : .requireApproval
        }
    }
}
