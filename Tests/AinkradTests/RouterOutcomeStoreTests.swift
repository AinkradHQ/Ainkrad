import AinkradHostRuntime
// Tests/AinkradTests/RouterOutcomeStoreTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("RouterOutcomeStore")
@MainActor
struct RouterOutcomeStoreTests {
    @Test func learnsPreferredModelFromSuccesses() {
        let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
        for _ in 0..<4 { s.recordSuccess(difficulty: .moderate, model: "gpt-5-mini") }
        s.recordFailure(difficulty: .moderate, model: "llama3.2")
        #expect(s.preferredModel(for: .moderate) == "gpt-5-mini")
    }

    @Test func overrideBiasesPreference() {
        let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
        for _ in 0..<3 { s.recordOverride(difficulty: .hard, model: "claude-opus-4-8") }
        #expect(s.preferredModel(for: .hard) == "claude-opus-4-8")
    }

    @Test func persistsAcrossReload() {
        let store = InMemoryPersistenceStore()
        let s = RouterOutcomeStore(persistence: store)
        for _ in 0..<3 { s.recordSuccess(difficulty: .trivial, model: "llama3.2") }
        let reloaded = RouterOutcomeStore(persistence: store)
        #expect(reloaded.successRate(difficulty: .trivial, model: "llama3.2") == 1.0)
    }

    @Test func failureMeasurablyDropsSuccessRate() {
        let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
        s.recordSuccess(difficulty: .moderate, model: "gpt-5-mini")
        s.recordSuccess(difficulty: .moderate, model: "gpt-5-mini")
        let before = s.successRate(difficulty: .moderate, model: "gpt-5-mini")
        s.recordFailure(difficulty: .moderate, model: "gpt-5-mini")
        let after = s.successRate(difficulty: .moderate, model: "gpt-5-mini")
        #expect(before == 1.0)
        #expect(after != nil && after! < before!)
    }

    @Test func repeatedIdenticalOutcomesConverge() {
        let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
        for _ in 0..<50 { s.recordSuccess(difficulty: .hard, model: "claude-opus-4-8") }
        #expect(s.successRate(difficulty: .hard, model: "claude-opus-4-8") == 1.0)
        // Adding more identical outcomes doesn't oscillate the rate away from 1.0.
        s.recordSuccess(difficulty: .hard, model: "claude-opus-4-8")
        #expect(s.successRate(difficulty: .hard, model: "claude-opus-4-8") == 1.0)
    }

    @Test func noQualifyingSamplesReturnsNilPreference() {
        let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
        s.recordSuccess(difficulty: .trivial, model: "llama3.2")
        // Only 1 sample, below the 3-sample qualification threshold, no overrides.
        #expect(s.preferredModel(for: .trivial) == nil)
    }

    @Test func equalOverrideCountsBreakTieByLowestModelIdDeterministically() {
        // Two models tied on override count for the same difficulty — the tiebreak must
        // be deterministic (lowest model id wins), not dependent on Dictionary iteration
        // order. Run it several times to catch any nondeterminism.
        for _ in 0..<20 {
            let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
            s.recordOverride(difficulty: .moderate, model: "zeta-model")
            s.recordOverride(difficulty: .moderate, model: "alpha-model")
            #expect(s.preferredModel(for: .moderate) == "alpha-model")
        }
    }

    @Test func equalSuccessRatesBreakTieByLowestModelIdDeterministically() {
        for _ in 0..<20 {
            let s = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
            for _ in 0..<3 { s.recordSuccess(difficulty: .hard, model: "zeta-model") }
            for _ in 0..<3 { s.recordSuccess(difficulty: .hard, model: "alpha-model") }
            #expect(s.preferredModel(for: .hard) == "alpha-model")
        }
    }
}
