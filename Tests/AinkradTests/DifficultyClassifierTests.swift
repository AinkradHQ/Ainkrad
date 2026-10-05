import Foundation
import Testing

@testable import Ainkrad

@Suite("DifficultyClassifier")
struct DifficultyClassifierTests {
    @Test func trivialShortMessageMapsToLocal() {
        let r = DifficultyClassifier.ruleScore(
            TaskSignal(estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
            lastMessage: "what time is it")
        #expect(r.difficulty == .trivial)
        #expect(DifficultyClassifier.minimumTier(for: r.difficulty) == .local)
    }

    @Test func reasoningHeavyMapsToHardPremium() {
        let r = DifficultyClassifier.ruleScore(
            TaskSignal(estimatedInputTokens: 8000, needsVision: false, needsTools: true, reasoningHeavy: true),
            lastMessage: "Prove that this distributed algorithm is correct and refactor the module.")
        #expect(r.difficulty == .hard)
        #expect(DifficultyClassifier.minimumTier(for: r.difficulty) == .premium)
    }

    @Test func escalatesOnFailureUntilCap() {
        #expect(
            DifficultyClassifier.shouldEscalate(
                confidence: 0.9, threshold: 0.5, toolFailed: true, selfCritiqueFailed: false, attempt: 1, maxAttempts: 3
            ))
        #expect(
            !DifficultyClassifier.shouldEscalate(
                confidence: 0.9, threshold: 0.5, toolFailed: true, selfCritiqueFailed: false, attempt: 3, maxAttempts: 3
            ))
    }

    @Test func escalatesOnLowConfidence() {
        #expect(
            DifficultyClassifier.shouldEscalate(
                confidence: 0.2, threshold: 0.5, toolFailed: false, selfCritiqueFailed: false, attempt: 1,
                maxAttempts: 3))
    }

    @Test func noModelStillReturnsRuleBasedDifficulty() {
        // Non-vacuous rule-only fallback: no cheap-model classifier is injected anywhere in
        // this type (it is a pure enum of static functions with no model dependency at all),
        // so ruleScore always returns a usable difficulty without any network/model call.
        let r = DifficultyClassifier.ruleScore(
            TaskSignal(estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
            lastMessage: "hello")
        #expect(r.confidence > 0 && r.confidence <= 1)
    }

    @Test func escalationCapIsHardBound() {
        // Even with maximally bad signals, attempt >= maxAttempts must never escalate further.
        #expect(
            !DifficultyClassifier.shouldEscalate(
                confidence: 0.0, threshold: 1.0, toolFailed: true, selfCritiqueFailed: true, attempt: 5, maxAttempts: 5)
        )
    }
}
