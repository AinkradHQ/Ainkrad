import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Router/RouterOutcomeStore.swift
import Foundation

/// Per-(difficulty, model) counters the router learns from: successes, failures, and
/// explicit user overrides (the user manually picked this model for this difficulty).
struct OutcomeStat: Codable, Equatable {
    var successes: Int = 0
    var failures: Int = 0
    var overrides: Int = 0
}

/// Persisted learning state for the Model Router (Task 13 consumes this via
/// `RouterOutcomeStore`). Keyed by `"<difficulty.rawValue>|<model>"`.
struct RouterOutcomeDocument: PersistableDocument {
    static let documentID = "router-outcomes"
    var stats: [String: OutcomeStat] = [:]

    init(stats: [String: OutcomeStat] = [:]) { self.stats = stats }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults) so a payload
    // missing newer keys never throws.
    private enum CodingKeys: String, CodingKey { case stats }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stats = try c.decodeIfPresent([String: OutcomeStat].self, forKey: .stats) ?? [:]
    }
}

/// Learns model preferences per task difficulty from recorded outcomes: turn
/// success/failure and explicit user overrides. Consulted by the Model Router (Task 13)
/// when ordering candidates, and updated by it after each turn.
///
/// Learning rule is a simple bounded counter per `(difficulty, model)` key — no decay,
/// no unbounded growth beyond one entry per distinct model actually used for a
/// difficulty. `successRate` is a plain ratio, so repeated identical outcomes converge
/// monotonically toward 0.0 or 1.0 and never oscillate.
@MainActor
final class RouterOutcomeStore {
    private var doc: RouterOutcomeDocument
    private let persistence: PersistenceStore
    /// Slice 1 seam — provided by Slice 1. Optional so Router (Slice 5) lands independently.
    private let profile: UserProfileStore?

    init(persistence: PersistenceStore, profile: UserProfileStore? = nil) {
        self.persistence = persistence
        self.profile = profile
        self.doc = persistence.load(RouterOutcomeDocument.self) ?? RouterOutcomeDocument()
    }

    private func key(_ d: Difficulty, _ m: String) -> String { "\(d.rawValue)|\(m)" }

    func recordSuccess(difficulty: Difficulty, model: String) {
        mutate(difficulty, model) { $0.successes += 1 }
    }

    func recordFailure(difficulty: Difficulty, model: String) {
        mutate(difficulty, model) { $0.failures += 1 }
    }

    func recordOverride(difficulty: Difficulty, model: String) {
        mutate(difficulty, model) { $0.overrides += 1 }
        // Slice 1 projection: a durable "prefers X for Y" fact, when Slice 1 is present.
        profile?.set(model, for: "router.preferred.\(difficulty.rawValue)")
    }

    func successRate(difficulty: Difficulty, model: String) -> Double? {
        guard let s = doc.stats[key(difficulty, model)] else { return nil }
        let total = s.successes + s.failures
        return total == 0 ? nil : Double(s.successes) / Double(total)
    }

    /// The highest success-rate model with >= 3 samples, or — if any overrides exist for
    /// this difficulty — the most-overridden-to model (explicit user choice wins).
    ///
    /// `Dictionary` iteration order is nondeterministic, so on an EQUAL override count or
    /// success rate, `.max(by:)` alone would nondeterministically pick whichever entry the
    /// dictionary happened to enumerate first. To make ties deterministic, the candidate
    /// entries are sorted by model id (ascending) before the `.max(by:)` scan — `max(by:)`
    /// keeps the first-seen element on a tie (its comparator only replaces on strict `<`),
    /// so sorting ascending first means the LOWEST model id wins a tie.
    func preferredModel(for difficulty: Difficulty) -> String? {
        let prefix = "\(difficulty.rawValue)|"
        let entries = doc.stats.filter { $0.key.hasPrefix(prefix) }
            .sorted { model(from: $0.key) < model(from: $1.key) }
        guard !entries.isEmpty else { return nil }

        if let override =
            entries
            .filter({ $0.value.overrides > 0 })
            .max(by: { $0.value.overrides < $1.value.overrides })
        {
            return model(from: override.key)
        }

        let qualified = entries.filter { $0.value.successes + $0.value.failures >= 3 }
        return qualified.max { a, b in
            rate(a.value) < rate(b.value)
        }.map { model(from: $0.key) }
    }

    private func rate(_ s: OutcomeStat) -> Double {
        let total = s.successes + s.failures
        return total == 0 ? 0 : Double(s.successes) / Double(total)
    }

    private func model(from key: String) -> String {
        guard let range = key.range(of: "|") else { return key }
        return String(key[range.upperBound...])
    }

    private func mutate(_ d: Difficulty, _ m: String, _ f: (inout OutcomeStat) -> Void) {
        var stat = doc.stats[key(d, m)] ?? OutcomeStat()
        f(&stat)
        doc.stats[key(d, m)] = stat
        persistence.save(doc)
    }
}
