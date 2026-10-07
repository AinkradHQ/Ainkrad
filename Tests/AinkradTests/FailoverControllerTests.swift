import Foundation
import Testing

@testable import Ainkrad

@Suite("FailoverController")
struct FailoverControllerTests {
    @Test func rateLimitRotatesKeyFirst() {
        let n = FailoverController.nextAttempt(
            models: ["a", "b"], keys: ["k1", "k2"],
            failedModel: "a", failedKeyIndex: 0, errorKind: .rateLimit)
        #expect(n?.model == "a")
        #expect(n?.keyIndex == 1)
    }

    @Test func advancesModelAfterKeysExhausted() {
        let n = FailoverController.nextAttempt(
            models: ["a", "b"], keys: ["k1", "k2"],
            failedModel: "a", failedKeyIndex: 1, errorKind: .rateLimit)
        #expect(n?.model == "b")
        #expect(n?.keyIndex == 0)
    }

    @Test func providerErrorAdvancesModel() {
        let n = FailoverController.nextAttempt(
            models: ["a", "b"], keys: ["k1"],
            failedModel: "a", failedKeyIndex: 0, errorKind: .providerError)
        #expect(n?.model == "b")
    }

    @Test func exhaustionReturnsNil() {
        let n = FailoverController.nextAttempt(
            models: ["a"], keys: ["k1"],
            failedModel: "a", failedKeyIndex: 0, errorKind: .providerError)
        #expect(n == nil)
    }

    @Test func quotaAlsoRotatesKeyFirst() {
        let n = FailoverController.nextAttempt(
            models: ["a"], keys: ["k1", "k2"],
            failedModel: "a", failedKeyIndex: 0, errorKind: .quota)
        #expect(n?.model == "a")
        #expect(n?.keyIndex == 1)
    }

    @Test func authErrorAdvancesModelRatherThanRotatingKey() {
        let n = FailoverController.nextAttempt(
            models: ["a", "b"], keys: ["k1", "k2"],
            failedModel: "a", failedKeyIndex: 0, errorKind: .auth)
        #expect(n?.model == "b")
        #expect(n?.keyIndex == 0)
    }

    @Test func noPriorFailureStartsAtFirstCandidate() {
        let n = FailoverController.nextAttempt(
            models: ["a", "b"], keys: ["k1"],
            failedModel: nil, failedKeyIndex: nil, errorKind: .providerError)
        #expect(n?.model == "a")
        #expect(n?.keyIndex == 0)
    }

    /// Proves the failover walk is bounded: repeatedly feeding the returned attempt back in
    /// as the "failed" one must terminate (reach nil) within model.count * key.count steps,
    /// never loop forever.
    @Test func exhaustiveWalkAcrossAllCandidatesIsBoundedAndTerminates() {
        let models = ["a", "b", "c"]
        let keys = ["k1", "k2"]
        var failedModel: String? = nil
        var failedKeyIndex: Int? = nil
        var steps = 0
        let maxSteps = models.count * keys.count + 1

        while steps < maxSteps {
            guard
                let next = FailoverController.nextAttempt(
                    models: models, keys: keys,
                    failedModel: failedModel, failedKeyIndex: failedKeyIndex,
                    errorKind: .rateLimit
                )
            else { break }
            failedModel = next.model
            failedKeyIndex = next.keyIndex
            steps += 1
        }

        // Must have terminated (found nil) strictly before the bound, and must have
        // visited every (model, key) pair exactly once.
        #expect(steps == models.count * keys.count)
    }

    /// A `FailoverController` instance driving an injected fake send closure that fails
    /// N times then succeeds — proves the controller advances through candidates and
    /// eventually succeeds.
    @Test func runSucceedsAfterInjectedFailuresThenSuccess() async {
        let models = ["a", "b", "c"]
        let keys = ["k1"]
        var attempts: [(model: String, keyIndex: Int)] = []

        let result = await FailoverController.run(models: models, keys: keys) {
            model, keyIndex -> FailoverController.SendOutcome<String> in
            attempts.append((model, keyIndex))
            if model == "c" {
                return .success("ok from \(model)")
            }
            return .failure(.providerError, "boom on \(model)")
        }

        switch result {
        case .success(let value, let model, let keyIndex):
            #expect(value == "ok from c")
            #expect(model == "c")
            #expect(keyIndex == 0)
        case .exhausted:
            Issue.record("expected eventual success")
        }
        #expect(attempts.map(\.model) == ["a", "b", "c"])
    }

    /// A fake send closure that always fails — proves the controller stops with a
    /// terminal error after exhaustion (bounded: exactly models.count * keys.count tries).
    /// Fix 2 (assistant-unusable root cause): the real NSURLError text for a
    /// connection-refused/local-server-down failure is "Could not connect to the
    /// server." — it contains "connect" but NOT "connection" or "could not reach",
    /// so before this fix `classify` fell through to `nil` (non-retryable) and
    /// failover never advanced past a dead local endpoint. A genuine content error
    /// (400) must still classify as non-retryable.
    @Test func connectionRefusedPhrasingsClassifyAsRetryableProviderError() {
        #expect(FailoverController.classify("Could not connect to the server.") == .providerError)
        #expect(FailoverController.classify("Streaming failed: Could not connect to the server.") == .providerError)
        #expect(FailoverController.classify("cannot connect to host") == .providerError)
        #expect(FailoverController.classify("Connection refused") == .providerError)
        #expect(FailoverController.classify("The network connection was lost.") == .providerError)
        #expect(FailoverController.classify("Error -1001: timed out") == .providerError)
        #expect(FailoverController.classify("Error -1009: offline") == .providerError)
    }

    @Test func genuineContentErrorsStayNonRetryableAlongsideConnectionRefusedFix() {
        #expect(FailoverController.classify("400 bad request") == nil)
        #expect(FailoverController.classify("404 not found") == nil)
    }

    @Test func runStopsWithTerminalErrorWhenAlwaysFailing() async {
        let models = ["a", "b"]
        let keys = ["k1", "k2"]
        var tries = 0

        let result = await FailoverController.run(models: models, keys: keys) {
            model, keyIndex -> FailoverController.SendOutcome<String> in
            tries += 1
            return .failure(.rateLimit, "provider says no (\(model)/\(keyIndex))")
        }

        switch result {
        case .success:
            Issue.record("expected exhaustion")
        case .exhausted(let lastMessage):
            #expect(lastMessage == "provider says no (b/1)")
        }
        #expect(tries == models.count * keys.count)
    }
}
