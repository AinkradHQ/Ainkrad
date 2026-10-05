import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Usage/UsageTracker.swift
import Foundation
import Observation

/// Persisted usage ledger: cumulative tokens/cost across all sessions, router
/// savings vs. always-premium, and a per-day breakdown keyed by `yyyy-MM-dd`.
struct UsageLedgerDocument: PersistableDocument {
    static let documentID = "usage-ledger"
    var cumulative: TokenUsage = .zero
    var cumulativeCostUSD: Double = 0
    var savingsUSD: Double = 0
    var byDay: [String: TokenUsage] = [:]

    init(
        cumulative: TokenUsage = .zero, cumulativeCostUSD: Double = 0,
        savingsUSD: Double = 0, byDay: [String: TokenUsage] = [:]
    ) {
        self.cumulative = cumulative
        self.cumulativeCostUSD = cumulativeCostUSD
        self.savingsUSD = savingsUSD
        self.byDay = byDay
    }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults).
    enum CodingKeys: String, CodingKey { case cumulative, cumulativeCostUSD, savingsUSD, byDay }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cumulative = try c.decodeIfPresent(TokenUsage.self, forKey: .cumulative) ?? .zero
        cumulativeCostUSD = try c.decodeIfPresent(Double.self, forKey: .cumulativeCostUSD) ?? 0
        savingsUSD = try c.decodeIfPresent(Double.self, forKey: .savingsUSD) ?? 0
        byDay = try c.decodeIfPresent([String: TokenUsage].self, forKey: .byDay) ?? [:]
    }
}

/// Turns per-turn `TokenUsage` telemetry into per-session + cumulative counts,
/// dollar cost (via `ModelPriceTable`), and router-savings accounting
/// (what free/cheap-first routing saved vs. always using the premium model),
/// persisted to disk under the `usage-ledger` document.
@MainActor
@Observable
final class UsageTracker {
    private(set) var session: TokenUsage = .zero
    private(set) var sessionCostUSD: Double = 0

    private var ledger: UsageLedgerDocument
    private let persistence: PersistenceStore
    private let prices: ModelPriceTable

    init(persistence: PersistenceStore, prices: ModelPriceTable) {
        self.persistence = persistence
        self.prices = prices
        self.ledger = persistence.load(UsageLedgerDocument.self) ?? UsageLedgerDocument()
    }

    /// Records one turn's usage against `model`. `baselineModel`, when given,
    /// is the premium model the router avoided; savings accrue as
    /// `max(0, baselineCost - actualCost)` for that turn. Unknown prices still
    /// count tokens but leave cost/savings math untouched (never a wrong number).
    func record(model: String, usage: TokenUsage, baselineModel: String?) {
        session = session + usage
        ledger.cumulative = ledger.cumulative + usage
        let key = Self.dayKey()
        ledger.byDay[key] = (ledger.byDay[key] ?? .zero) + usage

        if let cost = prices.cost(
            model: model, input: usage.input, output: usage.output,
            cacheRead: usage.cacheRead, cacheWrite: usage.cacheWrite)
        {
            sessionCostUSD += cost
            ledger.cumulativeCostUSD += cost

            if let baseline = baselineModel,
                let baseCost = prices.cost(
                    model: baseline, input: usage.input, output: usage.output,
                    cacheRead: usage.cacheRead, cacheWrite: usage.cacheWrite)
            {
                ledger.savingsUSD += max(0, baseCost - cost)
            }
        }

        persistence.save(ledger)
    }

    func resetSession() {
        session = .zero
        sessionCostUSD = 0
    }

    func cumulative() -> (TokenUsage, costUSD: Double, savingsUSD: Double) {
        (ledger.cumulative, ledger.cumulativeCostUSD, ledger.savingsUSD)
    }

    func today() -> TokenUsage {
        ledger.byDay[Self.dayKey()] ?? .zero
    }

    private static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}
