import AinkradHostRuntime
// Tests/AinkradTests/AgentWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("Agent wiring")
@MainActor
struct AgentWiringTests {
    @Test func cycleAdvancesActiveAgent() {
        let s = AgentStore(persistence: InMemoryPersistenceStore())
        s.setActive(BuiltInAgents.planID)
        s.cycleActive()
        #expect(s.active.id == BuiltInAgents.buildID)
        s.cycleActive()
        #expect(s.active.id == BuiltInAgents.planID)  // wraps
    }
}
