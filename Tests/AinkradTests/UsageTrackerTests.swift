import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("UsageTracker")
@MainActor
struct UsageTrackerTests {
    private func make() -> UsageTracker {
        UsageTracker(persistence: InMemoryPersistenceStore(), prices: ModelPriceTable())
    }

    @Test func accumulatesTokensAndCost() {
        let t = make()
        t.record(model: "gpt-5-mini", usage: TokenUsage(input: 1_000_000, output: 1_000_000), baselineModel: nil)
        #expect(t.session.input == 1_000_000)
        #expect(t.sessionCostUSD > 0)
    }

    @Test func recordsRouterSavingsVsBaseline() {
        let t = make()
        // Ran on gpt-5-mini but avoided gpt-5 → savings = costlyBaseline − actual.
        t.record(model: "gpt-5-mini", usage: TokenUsage(input: 1_000_000, output: 1_000_000), baselineModel: "gpt-5")
        #expect(t.cumulative().savingsUSD > 0)
    }

    @Test func unknownPriceCountsTokensNotCost() {
        let t = make()
        t.record(model: "unknown-xyz", usage: TokenUsage(input: 500, output: 500), baselineModel: nil)
        #expect(t.session.input == 500)
        #expect(t.sessionCostUSD == 0)
    }

    @Test func cumulativePersists() {
        let store = InMemoryPersistenceStore()
        let t = UsageTracker(persistence: store, prices: ModelPriceTable())
        t.record(model: "gpt-5-mini", usage: TokenUsage(input: 100, output: 100), baselineModel: nil)
        let reloaded = UsageTracker(persistence: store, prices: ModelPriceTable())
        #expect(reloaded.cumulative().0.input == 100)
    }
}
