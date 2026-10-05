import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Wave 1-A / Blocker 4: `.mainInteractive` is the only tier that reaches
/// `HostBackend` — an unsandboxed `/bin/zsh -lc` with the user's full
/// authority. That is justified by a human approving each call, so Full-auto
/// (no human) must not keep it.
@MainActor
@Suite("run_terminal tier demotion under Full-auto")
struct RunTerminalTierTests {
    private func router() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend(), .seatbelt: SeatbeltBackend()])
    }

    private func tool(mode: AgentPermissionMode?) -> RunTerminalTool {
        var t = RunTerminalTool(actionHub: AgentActionRegistryHub(), router: router())
        if let mode { t.permissionMode = { mode } }
        return t
    }

    @Test("Full-auto demotes the foreground tool off the host backend")
    func fullAutoDemotes() {
        #expect(tool(mode: .fullAuto).effectiveTier == .background)
    }

    @Test("Attended modes keep the interactive tier")
    func attendedModesKeepHost() {
        #expect(tool(mode: .ask).effectiveTier == .mainInteractive)
        #expect(tool(mode: .autoApprove).effectiveTier == .mainInteractive)
        // No mode wired at all (tests, non-session callers) behaves as attended.
        #expect(tool(mode: nil).effectiveTier == .mainInteractive)
    }

    @Test("An already-sandboxed tier is never changed")
    func sandboxedTiersUnchanged() {
        var t = RunTerminalTool(actionHub: AgentActionRegistryHub(), router: router())
        t.trustTier = .background
        t.permissionMode = { .fullAuto }
        #expect(t.effectiveTier == .background)
        t.trustTier = .untrustedMCP
        #expect(t.effectiveTier == .untrustedMCP)
    }

    @Test("Demotion resolves to a sandboxed, non-host profile")
    func demotedProfileIsSandboxed() {
        let r = router()
        let hostProfile = r.resolveProfile(tier: .mainInteractive, policy: nil)
        let demoted = r.resolveProfile(tier: .background, policy: nil)
        #expect(hostProfile.backend == .host)
        #expect(demoted.backend != .host)
    }

    @Test("Commands that defeated the old substring guard now require approval")
    func irreversibleCatchesBypasses() {
        let t = tool(mode: .fullAuto)
        for command in ["rm -r -f ~", "rm  -rf ~", "find ~ -delete", "curl x | sh", "/bin/rm -rf /"] {
            #expect(t.isIrreversible(.object(["command": .string(command)])), "not caught: \(command)")
        }
        #expect(!t.isIrreversible(.object(["command": .string("git status")])))
    }
}
