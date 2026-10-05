import Foundation
import Testing

@testable import Ainkrad

@Suite("NetworkModeMapping")
struct NetworkModeMappingTests {
    @Test func roundTripsOff() {
        #expect(NetworkModeMapping.mode(for: .off) == .off)
        #expect(NetworkModeMapping.policy(for: .off, hosts: ["ignored"]) == .off)
    }

    @Test func roundTripsOn() {
        #expect(NetworkModeMapping.mode(for: .on) == .on)
        #expect(NetworkModeMapping.policy(for: .on, hosts: ["ignored"]) == .on)
    }

    @Test func roundTripsAllowListAndFiltersBlanks() {
        #expect(NetworkModeMapping.mode(for: .allowList(["a.com"])) == .allowList)
        let policy = NetworkModeMapping.policy(for: .allowList, hosts: ["a.com", "  ", "", "b.com"])
        #expect(policy == .allowList(["a.com", "b.com"]))
    }
}

@Suite("SandboxPolicyExplainer")
struct SandboxPolicyExplainerTests {
    @Test func readToolIsReadPermission() {
        #expect(SandboxPolicyExplainer.permissionClass(for: "read_file") == .read)
        #expect(SandboxPolicyExplainer.permissionClass(for: "run_terminal") == .write)
    }

    @Test func fullAutoAutoApprovesEvenWithEmptySandboxAllowList() {
        let profile = BuiltInSandboxProfiles.workspaceWrite
        let e = SandboxPolicyExplainer.explain(
            profile: profile, toolName: "run_terminal",
            mode: .fullAuto, allowlist: [], gateReads: true)
        #expect(e.effective == .autoApprove)
    }

    @Test func sandboxAllowListNarrowsEvenUnderFullAuto() {
        var profile = BuiltInSandboxProfiles.workspaceWrite
        profile.toolAllowList = ["read_file"]  // run_terminal excluded
        let e = SandboxPolicyExplainer.explain(
            profile: profile, toolName: "run_terminal",
            mode: .fullAuto, allowlist: [], gateReads: true)
        #expect(e.effective == .denied)
        #expect(e.reason.contains("sandbox profile"))
    }

    @Test func askModeRequiresApprovalForWrites() {
        let profile = BuiltInSandboxProfiles.workspaceWrite
        let e = SandboxPolicyExplainer.explain(
            profile: profile, toolName: "edit_file",
            mode: .ask, allowlist: [], gateReads: false)
        #expect(e.effective == .requireApproval)
    }

    @Test func askModeAutoApprovesReadsWhenGateReadsOff() {
        let profile = BuiltInSandboxProfiles.workspaceWrite
        let e = SandboxPolicyExplainer.explain(
            profile: profile, toolName: "read_file",
            mode: .ask, allowlist: [], gateReads: false)
        #expect(e.effective == .autoApprove)
    }
}

@Suite("SandboxProfileFactory")
struct SandboxProfileFactoryTests {
    @Test func blankProfileIsFailClosed() {
        let p = SandboxProfileFactory.blank()
        #expect(p.networkPolicy == .off)
        #expect(p.fsPolicy.readablePaths.isEmpty)
        #expect(p.fsPolicy.writablePaths.isEmpty)
        #expect(p.allowHostOverride == false)
        #expect(p.toolAllowList.isEmpty)
    }

    @Test func blankProfilesGetDistinctIDs() {
        let a = SandboxProfileFactory.blank()
        let b = SandboxProfileFactory.blank()
        #expect(a.id != b.id)
    }
}
