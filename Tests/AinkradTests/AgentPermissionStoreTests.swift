import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentPermissionStore")
@MainActor
struct AgentPermissionStoreTests {
    @Test func defaultsToAsk() {
        let ws = UUID()
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { ws })
        #expect(store.mode == .ask)
    }

    @Test func setModePersistsPerWorkspace() {
        let wsA = UUID()
        let wsB = UUID()
        var active = wsA
        let persistence = InMemoryPersistenceStore()
        let store = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { active })
        store.setMode(.fullAuto)
        #expect(store.mode == .fullAuto)
        active = wsB
        #expect(store.mode == .ask)  // other workspace unaffected

        // Reload from the same persistence: workspace A's mode survives.
        active = wsA
        let reloaded = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { active })
        #expect(reloaded.mode == .fullAuto)
    }

    @Test func gateReadsDefaultsToTrue() {
        let ws = UUID()
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { ws })
        #expect(store.gateReads == true)
    }

    @Test func setGateReadsPersistsAcrossReload() {
        let ws = UUID()
        let persistence = InMemoryPersistenceStore()
        let store = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        store.setGateReads(false)
        #expect(store.gateReads == false)

        let reloaded = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        #expect(reloaded.gateReads == false)
    }

    @Test func addToAllowlistAddsToolName() {
        let ws = UUID()
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { ws })
        store.addToAllowlist("run_terminal")
        #expect(store.allowlist.contains("run_terminal"))
    }

    @Test func addToAllowlistIsIdempotent() {
        let ws = UUID()
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { ws })
        store.addToAllowlist("run_terminal")
        store.addToAllowlist("run_terminal")
        #expect(store.allowlist.count == 1)
    }

    @Test func addToAllowlistSurvivesReload() {
        let ws = UUID()
        let persistence = InMemoryPersistenceStore()
        let store = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        store.addToAllowlist("run_terminal")

        let reloaded = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { ws })
        #expect(reloaded.allowlist.contains("run_terminal"))
    }

    @Test func removeFromAllowlistRemovesToolName() {
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { UUID() })
        store.addToAllowlist("run_terminal")
        store.removeFromAllowlist("run_terminal")
        #expect(!store.allowlist.contains("run_terminal"))
    }

    @Test func removeFromAllowlistIsNoOpWhenAbsent() {
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { UUID() })
        store.addToAllowlist("edit_file")
        store.removeFromAllowlist("run_terminal")
        #expect(store.allowlist == ["edit_file"])
    }

    @Test func clearAllowlistEmpties() {
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { UUID() })
        store.addToAllowlist("edit_file")
        store.addToAllowlist("run_terminal")
        store.clearAllowlist()
        #expect(store.allowlist.isEmpty)
    }

    @Test func removeFromAllowlistPersistsAcrossReload() {
        let persistence = InMemoryPersistenceStore()
        let store = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        store.addToAllowlist("edit_file")
        store.addToAllowlist("run_terminal")
        store.removeFromAllowlist("edit_file")

        let reloaded = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        #expect(reloaded.allowlist == ["run_terminal"])
    }

    @Test func cycleAdvancesModeAndWraps() {
        let ws = UUID()
        let store = AgentPermissionStore(persistence: InMemoryPersistenceStore(), currentWorkspaceID: { ws })
        #expect(store.mode == .ask)
        store.cycle()
        #expect(store.mode == .autoApprove)
        store.cycle()
        #expect(store.mode == .fullAuto)
        store.cycle()
        #expect(store.mode == .ask)  // wraps back around
    }
}
