import Testing

@testable import Ainkrad

@Suite("AgentPermissionPolicy")
struct AgentPermissionModelTests {
    private func decide(
        _ p: ToolPermissionClass, _ mode: AgentPermissionMode,
        name: String = "edit_file", allow: Set<String> = [],
        gateReads: Bool, isIrreversible: Bool = false,
        isTrusted: Bool = false
    ) -> PermissionDecision {
        AgentPermissionPolicy.decide(
            toolPermission: p, toolName: name, mode: mode, allowlist: allow,
            gateReads: gateReads, isIrreversible: isIrreversible, isTrusted: isTrusted)
    }

    @Test func askAutoApprovesReadsGatesWrites() {
        #expect(decide(.read, .ask, gateReads: false) == .autoApprove)
        #expect(decide(.write, .ask, gateReads: false) == .requireApproval)
    }

    @Test func autoApproveGatesWritesUnlessAllowlisted() {
        #expect(decide(.read, .autoApprove, gateReads: false) == .autoApprove)
        #expect(decide(.write, .autoApprove, gateReads: false) == .requireApproval)
        #expect(decide(.write, .autoApprove, name: "edit_file", allow: ["edit_file"], gateReads: false) == .autoApprove)
    }

    @Test func fullAutoApprovesEverything() {
        #expect(decide(.read, .fullAuto, gateReads: false) == .autoApprove)
        #expect(decide(.write, .fullAuto, gateReads: false) == .autoApprove)
    }

    @Test func gateReadsAskGatesReads() {
        #expect(decide(.read, .ask, gateReads: true) == .requireApproval)
        #expect(decide(.write, .ask, gateReads: true) == .requireApproval)
    }

    @Test func gateReadsAutoApproveGatesReadsUnlessAllowlisted() {
        #expect(decide(.read, .autoApprove, gateReads: true) == .requireApproval)
        #expect(decide(.read, .autoApprove, name: "read_file", allow: ["read_file"], gateReads: true) == .autoApprove)
        #expect(decide(.write, .autoApprove, gateReads: true) == .requireApproval)
    }

    @Test func gateReadsFullAutoStillApprovesEverything() {
        #expect(decide(.read, .fullAuto, gateReads: true) == .autoApprove)
        #expect(decide(.write, .fullAuto, gateReads: true) == .autoApprove)
    }

    @Test("fullAuto still gates irreversible calls")
    func fullAutoGatesIrreversible() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "git_op", mode: .fullAuto,
            allowlist: [], gateReads: false, isIrreversible: true)
        #expect(d == .requireApproval)
    }

    @Test("fullAuto auto-approves reversible calls")
    func fullAutoAutoApprovesReversible() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "run_terminal", mode: .fullAuto,
            allowlist: [], gateReads: false, isIrreversible: false)
        #expect(d == .autoApprove)
    }

    @Test("isIrreversible does not change ask behavior (writes already gated)")
    func nonFullAutoUnaffectedByIrreversible() {
        // Writes already require approval in .ask, regardless of isIrreversible.
        #expect(decide(.write, .ask, gateReads: false, isIrreversible: true) == .requireApproval)
        #expect(decide(.write, .ask, gateReads: false, isIrreversible: false) == .requireApproval)
    }

    @Test("autoApprove: allowlisted tool + irreversible call still requires approval (bypass closed)")
    func autoApproveAllowlistedIrreversibleStillGated() {
        // This is the bug: "Allow always" allowlists the whole tool NAME, so a later
        // irreversible call (e.g. `rm -rf`) through that same tool must NOT slip through.
        #expect(
            decide(
                .write, .autoApprove, name: "run_terminal", allow: ["run_terminal"], gateReads: false,
                isIrreversible: true) == .requireApproval)
    }

    @Test("autoApprove: allowlisted tool + reversible call is unchanged (still auto-approves)")
    func autoApproveAllowlistedReversibleUnchanged() {
        #expect(
            decide(
                .write, .autoApprove, name: "edit_file", allow: ["edit_file"], gateReads: false, isIrreversible: false)
                == .autoApprove)
    }

    @Test func memoryToolIsExemptInAskMode() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .memory, toolName: "memory_write",
            mode: .ask, allowlist: [], gateReads: true, isIrreversible: false)
        #expect(d == .autoApprove)
    }

    @Test func memoryToolExemptEvenWhenGateReadsOn() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .memory, toolName: "memory_write",
            mode: .autoApprove, allowlist: [], gateReads: true, isIrreversible: false)
        #expect(d == .autoApprove)
    }

    @Test func memoryToolStillGatedIfMarkedIrreversible() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .memory, toolName: "memory_write",
            mode: .ask, allowlist: [], gateReads: true, isIrreversible: true)
        #expect(d == .requireApproval)
    }

    // MARK: - Task 9: per-server MCP trust

    @Test("(a) trusted MCP tool auto-approves even in Ask mode")
    func trustedMCPToolAutoApprovesInAskMode() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "mcp/web/search",
            mode: .ask, allowlist: [], gateReads: true, isIrreversible: false, isTrusted: true)
        #expect(d == .autoApprove)
    }

    @Test("(b) trusted IRREVERSIBLE tool still requires approval — trust never bypasses the backstop")
    func trustedIrreversibleStillRequiresApproval() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "mcp/web/rm",
            mode: .fullAuto, allowlist: [], gateReads: false, isIrreversible: true, isTrusted: true)
        #expect(d == .requireApproval)
    }

    @Test("(c) .memory exemption still works standalone (composition: isTrusted defaults false)")
    func memoryExemptionUnaffectedByTrustAddition() {
        #expect(decide(.memory, .ask, gateReads: true, isIrreversible: false) == .autoApprove)
    }

    @Test("(c) .memory and isTrusted compose: either alone is sufficient to auto-approve")
    func memoryAndTrustCompose() {
        // Non-memory, non-trusted write: normal gate applies.
        #expect(decide(.write, .ask, gateReads: true, isIrreversible: false, isTrusted: false) == .requireApproval)
        // Trusted (not memory) write: exempt via isTrusted.
        #expect(decide(.write, .ask, gateReads: true, isIrreversible: false, isTrusted: true) == .autoApprove)
        // Memory (not trusted) write: exempt via .memory, as before.
        #expect(decide(.memory, .ask, gateReads: true, isIrreversible: false, isTrusted: false) == .autoApprove)
    }

    @Test("(d) untrusted MCP tool still hits the normal gate (Ask mode requires approval)")
    func untrustedMCPToolStillGatedInAskMode() {
        let d = AgentPermissionPolicy.decide(
            toolPermission: .write, toolName: "mcp/web/search",
            mode: .ask, allowlist: [], gateReads: true, isIrreversible: false, isTrusted: false)
        #expect(d == .requireApproval)
    }

    @Test("default isTrusted (omitted) preserves pre-existing call-site behavior")
    func isTrustedDefaultsFalse() {
        #expect(decide(.write, .ask, gateReads: false) == .requireApproval)
    }
}
