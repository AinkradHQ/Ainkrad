import Foundation

/// Classification of a send failure used to decide the failover strategy. Only errors the
/// caller has already recognized as retryable-against-a-different-candidate reach here —
/// a genuine user/content error (which would fail identically against every model/key) is
/// never classified into one of these cases upstream, so `FailoverController` never needs
/// to special-case "don't retry" itself: every kind it sees IS worth advancing on.
enum FailoverErrorKind: Sendable {
    case rateLimit
    case quota
    case providerError
    case auth
}

/// Walks an ordered list of (model, auth-key) candidates around a send, advancing on
/// retryable provider errors and stopping — bounded — once every candidate has been tried.
///
/// Strategy: on `.rateLimit` / `.quota`, rotate to the NEXT KEY on the SAME model first
/// (the model may still work, the key is just throttled); once keys are exhausted for that
/// model — or immediately for `.providerError` / `.auth` — advance to the NEXT MODEL and
/// reset to the first key. This makes forward progress strictly monotonic over the
/// `(modelIndex, keyIndex)` lexicographic order, so a walk that keeps feeding the returned
/// attempt back in visits each of the `models.count * keys.count` combinations at most
/// once and then returns `nil` — it can never cycle.
struct FailoverController {
    /// Outcome of one attempt fed into `run`.
    enum SendOutcome<Success: Sendable>: Sendable {
        case success(Success)
        case failure(FailoverErrorKind, String)
    }

    /// Final result of a bounded `run` walk.
    enum RunResult<Success: Sendable>: Sendable {
        case success(Success, model: String, keyIndex: Int)
        /// Failover exhausted every candidate; carries the LAST provider's error message,
        /// per the design: a clear terminal error in the transcript.
        case exhausted(lastMessage: String)
    }

    /// Pure step function: given the just-failed `(model, keyIndex)` (or `nil` for the very
    /// first attempt) and why it failed, returns the next candidate to try, or `nil` once
    /// every `(model, key)` combination has been exhausted.
    static func nextAttempt(
        models: [String],
        keys: [String],
        failedModel: String?,
        failedKeyIndex: Int?,
        errorKind: FailoverErrorKind
    ) -> (model: String, keyIndex: Int)? {
        guard let failedModel, let mi = models.firstIndex(of: failedModel) else {
            return models.first.map { ($0, 0) }
        }
        let ki = failedKeyIndex ?? 0
        // Rate-limit / quota: rotate to the next KEY on the same model first.
        if errorKind == .rateLimit || errorKind == .quota, ki + 1 < keys.count {
            return (failedModel, ki + 1)
        }
        // Otherwise advance the MODEL (reset to first key).
        if mi + 1 < models.count { return (models[mi + 1], 0) }
        return nil
    }

    /// Drives `send` across candidates chosen by `nextAttempt` until it succeeds or every
    /// candidate has been exhausted. Bounded to at most `models.count * keys.count` calls
    /// to `send` — `nextAttempt`'s monotonic ordering guarantees termination, and this loop
    /// additionally enforces the same bound directly so a future change to `nextAttempt`
    /// could never make this loop infinite.
    static func run<Success: Sendable>(
        models: [String],
        keys: [String],
        send: (_ model: String, _ keyIndex: Int) async -> SendOutcome<Success>
    ) async -> RunResult<Success> {
        guard
            var current = nextAttempt(
                models: models, keys: keys, failedModel: nil, failedKeyIndex: nil, errorKind: .providerError
            )
        else {
            return .exhausted(lastMessage: "no candidates configured")
        }

        let maxAttempts = max(models.count * keys.count, 1)
        var lastMessage = ""
        for _ in 0..<maxAttempts {
            switch await send(current.model, current.keyIndex) {
            case .success(let value):
                return .success(value, model: current.model, keyIndex: current.keyIndex)
            case .failure(let kind, let message):
                lastMessage = message
                guard
                    let next = nextAttempt(
                        models: models, keys: keys,
                        failedModel: current.model, failedKeyIndex: current.keyIndex,
                        errorKind: kind
                    )
                else {
                    return .exhausted(lastMessage: message)
                }
                current = next
            }
        }
        return .exhausted(lastMessage: lastMessage)
    }

    /// Classifies a provider send failure into a `FailoverErrorKind`, or `nil` when the
    /// error is a genuine content/user error that would fail identically against every
    /// candidate (e.g. a 400 bad request) — those must NEVER be retried, so this is the
    /// one place upstream callers (Task 16's `AgentSession`) consult before feeding a
    /// failure into `run`/`nextAttempt`.
    ///
    /// Host providers currently surface only a best-effort message string (no threaded
    /// HTTP status code — see Task 16's report for that follow-up), so classification is
    /// substring-based over the provider's error message. Order matters: rate-limit/quota/
    /// auth phrasing is checked before the generic 5xx/transient bucket, and an explicit
    /// 400/404/"bad request"/"invalid request" match short-circuits to `nil` even if some
    /// other retryable-sounding word also appears.
    static func classify(_ message: String) -> FailoverErrorKind? {
        let m = message.lowercased()

        // Genuine content/user errors — never retryable.
        if m.contains("400") || m.contains("404") || m.contains("bad request")
            || m.contains("invalid request") || m.contains("invalid_request_error")
            || m.contains("not found")
        {
            return nil
        }

        if m.contains("429") || m.contains("rate limit") || m.contains("rate_limit")
            || m.contains("too many requests")
        {
            return .rateLimit
        }

        if m.contains("quota") || m.contains("insufficient_quota") || m.contains("billing")
            || m.contains("payment required") || m.contains("402")
        {
            return .quota
        }

        if m.contains("401") || m.contains("403") || m.contains("unauthorized")
            || m.contains("authentication") || m.contains("invalid api key")
            || m.contains("invalid_api_key") || m.contains("forbidden")
        {
            return .auth
        }

        if m.contains("500") || m.contains("502") || m.contains("503") || m.contains("504")
            || m.contains("529") || m.contains("overloaded") || m.contains("timed out")
            || m.contains("timeout") || m.contains("bad gateway") || m.contains("service unavailable")
            || m.contains("gateway timeout") || m.contains("internal server error")
            || m.contains("could not reach") || m.contains("connection")
            // Connection-refused / unreachable-endpoint phrasings (e.g. a down local
            // Ollama/LM Studio server) — the real NSURLError text is "Could not connect
            // to the server.", which contains "connect" but NOT "connection", so it fell
            // through to the non-retryable default without these. Without this, failover
            // never advances past a dead local endpoint to a reachable candidate.
            || m.contains("could not connect") || m.contains("cannot connect")
            || m.contains("connection refused") || m.contains("network connection was lost")
            || m.contains("-1004") || m.contains("-1001") || m.contains("-1009")
        {
            return .providerError
        }

        // Unknown shape: conservative default is non-retryable rather than risk looping
        // through every candidate for an error nobody has recognized as transient.
        return nil
    }
}
