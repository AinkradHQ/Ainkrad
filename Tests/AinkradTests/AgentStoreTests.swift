import AinkradHostRuntime
// Tests/AinkradTests/AgentStoreTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentStore")
@MainActor
struct AgentStoreTests {
    private func store() -> AgentStore { AgentStore(persistence: InMemoryPersistenceStore()) }

    @Test func shipsBuiltInsAndDefaultsActiveToBuild() {
        let s = store()
        #expect(s.agents.contains { $0.id == BuiltInAgents.planID })
        #expect(s.agents.contains { $0.id == BuiltInAgents.buildID })
        #expect(s.active.id == BuiltInAgents.buildID)
    }

    @Test func planIsReadOnly() {
        let plan = BuiltInAgents.plan
        #expect(!plan.toolPolicy.allows(toolName: "edit_file", permission: .write))
        #expect(plan.toolPolicy.allows(toolName: "read_file", permission: .read))
    }

    @Test func addAndSetActivePersists() {
        let s = store()
        let a = s.add(.custom(name: "Reviewer", instructions: "x"))
        s.setActive(a.id)
        #expect(s.active.id == a.id)
        let reloaded = AgentStore(persistence: s.persistenceForTesting)
        #expect(reloaded.active.id == a.id)
    }

    @Test func builtInsAreNonDeletable() {
        let s = store()
        s.delete(BuiltInAgents.planID)
        #expect(s.agents.contains { $0.id == BuiltInAgents.planID })
    }

    @Test func deletingActiveCustomFallsBackToBuild() {
        let s = store()
        let a = s.add(.custom(name: "R", instructions: "x"))
        s.setActive(a.id)
        s.delete(a.id)
        #expect(s.active.id == BuiltInAgents.buildID)
    }

    @Test func cloneProducesEditableCopy() {
        let s = store()
        let copy = s.clone(BuiltInAgents.planID)
        #expect(!copy.builtin)
        #expect(copy.name.contains("Copy"))
        #expect(s.agents.contains { $0.id == copy.id })
    }
}
