import Foundation
import Testing

@testable import Ainkrad

@Suite("SandboxPermissionPolicy")
struct SandboxPermissionPolicyTests {
    @Test func allAllowAutoApproves() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: nil, sandboxAllowList: [], toolName: "run_terminal")
        #expect(e.effective == .autoApprove)
    }

    @Test func gateRequireApprovalIsNotLoosened() {
        let e = SandboxPermissionPolicy.compose(
            gate: .requireApproval, agentAllowList: ["run_terminal"],
            sandboxAllowList: ["run_terminal"], toolName: "run_terminal")
        #expect(e.effective == .requireApproval)  // sandbox/agent allow can't upgrade to auto
    }

    @Test func agentAllowListExclusionDenies() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: ["read_file"], sandboxAllowList: [],
            toolName: "run_terminal")
        #expect(e.effective == .denied)
        #expect(e.reason.contains("Agent"))
    }

    @Test func sandboxAllowListExclusionDenies() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: nil, sandboxAllowList: ["read_file"],
            toolName: "run_terminal")
        #expect(e.effective == .denied)
        #expect(e.reason.contains("sandbox"))
    }

    @Test func mostRestrictiveWinsAcrossLayers() {
        // agent denies even though gate would auto-approve and sandbox allows.
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: [], sandboxAllowList: ["run_terminal"],
            toolName: "run_terminal")
        #expect(e.effective == .denied)
    }

    @Test func hardDeniedByAgentCannotBeUnDeniedBySandboxOrGate() {
        // Agent excludes, sandbox includes, gate autoApprove — denied wins regardless.
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: ["read_file"], sandboxAllowList: ["run_terminal"],
            toolName: "run_terminal")
        #expect(e.effective == .denied)
    }

    @Test func hardDeniedBySandboxCannotBeUnDeniedByAgentOrGate() {
        // Sandbox excludes, agent includes, gate autoApprove — denied wins regardless.
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: ["run_terminal"], sandboxAllowList: ["read_file"],
            toolName: "run_terminal")
        #expect(e.effective == .denied)
    }

    @Test func gateRequireApprovalWithSandboxExclusionStaysDenied() {
        // denied is more restrictive than requireApproval, must not soften to requireApproval.
        let e = SandboxPermissionPolicy.compose(
            gate: .requireApproval, agentAllowList: nil, sandboxAllowList: ["read_file"],
            toolName: "run_terminal")
        #expect(e.effective == .denied)
    }

    @Test func nilAgentAllowListDoesNotRestrict() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: nil, sandboxAllowList: [], toolName: "anything")
        #expect(e.effective == .autoApprove)
    }

    @Test func emptySandboxAllowListDoesNotRestrict() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: nil, sandboxAllowList: [], toolName: "anything")
        #expect(e.effective == .autoApprove)
    }

    @Test func explanationNamesBlockingLayerForAgent() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: ["read_file"], sandboxAllowList: [],
            toolName: "run_terminal")
        #expect(e.reason.contains("Agent"))
        #expect(e.reason.contains("run_terminal"))
    }

    @Test func explanationNamesBlockingLayerForSandbox() {
        let e = SandboxPermissionPolicy.compose(
            gate: .autoApprove, agentAllowList: nil, sandboxAllowList: ["read_file"],
            toolName: "run_terminal")
        #expect(e.reason.contains("sandbox"))
        #expect(e.reason.contains("run_terminal"))
    }

    // Exhaustive truth-table: composed result is never more permissive than any
    // single layer, across every combination of gate x agent-inclusion x sandbox-inclusion.
    @Test func neverMorePermissiveThanAnyLayer() {
        let rank: [EffectivePermission: Int] = [.denied: 0, .requireApproval: 1, .autoApprove: 2]
        let tool = "run_terminal"
        for gate in [PermissionDecision.autoApprove, .requireApproval] {
            for agentIncludes in [true, false] {
                for sandboxIncludes in [true, false] {
                    let agentList: Set<String>? = agentIncludes ? [tool] : []
                    let sandboxList: Set<String> = sandboxIncludes ? [tool] : ["other_tool"]
                    let e = SandboxPermissionPolicy.compose(
                        gate: gate, agentAllowList: agentList, sandboxAllowList: sandboxList,
                        toolName: tool)

                    let gateRank = rank[gate == .autoApprove ? .autoApprove : .requireApproval]!
                    let agentRank = agentIncludes ? 2 : 0
                    let sandboxRank = sandboxIncludes ? 2 : 0
                    let expectedCeiling = min(gateRank, agentRank, sandboxRank)

                    #expect(rank[e.effective]! <= expectedCeiling)
                }
            }
        }
    }
}
