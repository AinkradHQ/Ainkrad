import AinkradHostRuntime
// Tests/AinkradTests/SageRuntimeOptionsTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SageRuntimeOptions")
@MainActor
struct SageRuntimeOptionsTests {
    @Test func togglesPersist() {
        let store = InMemoryPersistenceStore()
        let s = RuntimeOptionsStore(persistence: store)
        s.setVerbose(true)
        s.setThinkLevel("high")
        s.pinModel("gpt-5")
        let reloaded = RuntimeOptionsStore(persistence: store)
        #expect(reloaded.options.verbose)
        #expect(reloaded.options.thinkLevel == "high")
        #expect(reloaded.options.pinnedModel == "gpt-5")
    }

    @Test func defaultsAreSensible() {
        let store = InMemoryPersistenceStore()
        let s = RuntimeOptionsStore(persistence: store)
        #expect(!s.options.verbose)
        #expect(!s.options.trace)
        #expect(s.options.thinkLevel == "medium")
        #expect(s.options.pinnedModel == nil)
        #expect(s.options.routerPolicy == .saveMoney)
    }

    @Test func resetForNewSessionClearsThePinOnly() {
        let store = InMemoryPersistenceStore()
        let s = RuntimeOptionsStore(persistence: store)
        s.setVerbose(true)
        s.pinModel("gpt-5")
        s.resetForNewSession()
        #expect(s.options.pinnedModel == nil)
        #expect(s.options.verbose)  // verbose is a standing preference, not per-session
    }
}
