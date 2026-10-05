import Foundation

/// How hard a turn is judged to be — drives the minimum `ModelTier` the Model Router
/// (Task 13) requires when selecting a candidate model.
enum Difficulty: Int, Comparable, Sendable {
    case trivial = 0
    case moderate = 1
    case hard = 2
    static func < (l: Difficulty, r: Difficulty) -> Bool { l.rawValue < r.rawValue }
}

/// A difficulty judgment plus the classifier's confidence in it (`0...1`).
struct ClassifierResult: Equatable, Sendable {
    let difficulty: Difficulty
    let confidence: Double
}

/// Rule-based (and, in Task 13, optionally cheap-model-assisted) task-difficulty scoring
/// plus the bounded escalation math the Model Router uses to bump a task up a tier.
///
/// `ruleScore` is pure and synchronous — it never calls a model, never blocks, and never
/// throws, so it is always available as the fallback path when an optional cheap/free
/// classifier model (injected as an async closure in `ModelRouter`, Task 13) is unavailable,
/// not configured, or errors.
enum DifficultyClassifier {
    private static let reasoningKeywords = [
        "prove", "refactor", "design", "architect", "debug",
        "optimize", "algorithm", "why", "explain", "analyze",
    ]

    /// Pure heuristic scoring over a `TaskSignal` + the last user message: length, reasoning
    /// keywords, and declared size/tool-use features. Never blocks, never throws — this is
    /// the rule-only fallback the router falls back to when no cheap-model classifier is
    /// available.
    static func ruleScore(_ signal: TaskSignal, lastMessage: String) -> ClassifierResult {
        let lower = lastMessage.lowercased()
        let hasReasoning = signal.reasoningHeavy || reasoningKeywords.contains { lower.contains($0) }
        let long = signal.estimatedInputTokens > 4000 || lastMessage.count > 400

        if hasReasoning && (long || signal.needsTools) {
            return ClassifierResult(difficulty: .hard, confidence: 0.8)
        }
        if hasReasoning || long || signal.needsTools {
            return ClassifierResult(difficulty: .moderate, confidence: 0.65)
        }
        return ClassifierResult(difficulty: .trivial, confidence: 0.7)
    }

    /// The minimum `ModelTier` a difficulty requires.
    static func minimumTier(for difficulty: Difficulty) -> ModelTier {
        switch difficulty {
        case .trivial: return .local
        case .moderate: return .cheapPaid
        case .hard: return .premium
        }
    }

    /// Whether the router should escalate a task up a tier: low classifier confidence,
    /// a tool/parse failure, or a self-critique quality miss — bounded by `maxAttempts` so
    /// escalation can never loop unbounded.
    static func shouldEscalate(
        confidence: Double, threshold: Double, toolFailed: Bool,
        selfCritiqueFailed: Bool, attempt: Int, maxAttempts: Int
    ) -> Bool {
        guard attempt < maxAttempts else { return false }
        return confidence < threshold || toolFailed || selfCritiqueFailed
    }
}
