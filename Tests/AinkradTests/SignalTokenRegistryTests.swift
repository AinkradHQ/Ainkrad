import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

/// Uses the real `InMemorySecretStore` from `AinkradHostRuntime` rather than a
/// hand-rolled double: the plan sketched one, but a fixture that already exists
/// and is used by the rest of the suite cannot drift from the protocol.
@MainActor
@Suite("Signal token registry and rate limiter")
struct SignalTokenRegistryTests {

    // MARK: - Token registry

    @Test("a minted token maps back to exactly its source")
    func mintAndResolve() {
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        let token = registry.mint(for: .app(appID: "raven"))
        #expect(registry.source(for: token) == .app(appID: "raven"))
    }

    @Test("tokens are unguessable and never reused across sources")
    func tokensAreDistinct() {
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        let a = registry.mint(for: .app(appID: "raven"))
        let b = registry.mint(for: .app(appID: "quest"))
        #expect(a != b)
        #expect(a.count >= 32, "a short token is a guessable token")
        #expect(registry.source(for: b) == .app(appID: "quest"))
    }

    @Test("re-minting for a source replaces the old token, which stops working")
    func remintRevokesTheOld() {
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        let old = registry.mint(for: .host)
        let new = registry.mint(for: .host)
        #expect(registry.source(for: new) == .host)
        #expect(registry.source(for: old) == nil,
                "a rotated credential must stop working immediately")
    }

    @Test("an unknown token resolves to nothing")
    func unknownToken() {
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        #expect(registry.source(for: "not-a-token") == nil)
    }

    @Test("revocation takes effect immediately")
    func revoke() {
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        let token = registry.mint(for: .app(appID: "raven"))
        registry.revoke(.app(appID: "raven"))
        #expect(registry.source(for: token) == nil)
    }

    @Test("tokens survive a restart because they live in the secret store")
    func persistence() {
        let secrets = InMemorySecretStore()
        let token = SignalTokenRegistry(secrets: secrets).mint(for: .app(appID: "raven"))
        #expect(SignalTokenRegistry(secrets: secrets).source(for: token) == .app(appID: "raven"))
    }

    @Test("a revoked source is forgotten across a restart too")
    func revocationPersists() {
        // The index is the only record of WHICH sources hold tokens, so a
        // revocation that removed the secret but left the index would come
        // back as a token that resolves to nothing on the next launch — or,
        // worse, resurrect on the next mint.
        let secrets = InMemorySecretStore()
        let first = SignalTokenRegistry(secrets: secrets)
        let token = first.mint(for: .app(appID: "raven"))
        first.revoke(.app(appID: "raven"))
        #expect(SignalTokenRegistry(secrets: secrets).source(for: token) == nil)
    }

    @Test("several sources all survive a restart, not just the last one")
    func persistenceAcrossSources() {
        let secrets = InMemorySecretStore()
        let minting = SignalTokenRegistry(secrets: secrets)
        let raven = minting.mint(for: .app(appID: "raven"))
        let sage = minting.mint(for: .sage)
        let host = minting.mint(for: .host)

        let reloaded = SignalTokenRegistry(secrets: secrets)
        #expect(reloaded.source(for: raven) == .app(appID: "raven"))
        #expect(reloaded.source(for: sage) == .sage)
        #expect(reloaded.source(for: host) == .host)
    }

    @Test("the peer hash identifies a peer without revealing its token")
    func peerHashHidesTheToken() {
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        let token = registry.mint(for: .host)
        let hash = registry.peerHash(for: token)
        #expect(!hash.contains(token))
        #expect(hash == registry.peerHash(for: token), "stable, so rate-limit rows coalesce")
    }

    @Test("an unknown token still hashes, so a rejection can name its peer")
    func peerHashOfUnknownToken() {
        // Rejection logging runs on tokens that did NOT resolve — that is the
        // interesting case — so this must not depend on the token being known.
        let registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        let hash = registry.peerHash(for: "never-minted")
        #expect(!hash.isEmpty)
        #expect(!hash.contains("never-minted"))
    }

    // MARK: - Rate limiter

    @Test("the rate limiter allows a burst, then throttles, then recovers")
    func rateLimiting() {
        let limiter = SignalRateLimiter(limit: 20, window: 10)
        let start = Date(timeIntervalSince1970: 1000)
        for i in 0..<20 {
            #expect(limiter.allow(.host, now: start.addingTimeInterval(Double(i) * 0.1)) == .allowed)
        }
        #expect(limiter.allow(.host, now: start.addingTimeInterval(2)) == .throttled)
        #expect(limiter.allow(.host, now: start.addingTimeInterval(11)) == .allowed,
                "the window rolls; a throttle is not a ban")
    }

    @Test("one source's flood does not throttle another")
    func rateLimitIsPerSource() {
        let limiter = SignalRateLimiter(limit: 2, window: 10)
        let now = Date()
        _ = limiter.allow(.app(appID: "noisy"), now: now)
        _ = limiter.allow(.app(appID: "noisy"), now: now)
        #expect(limiter.allow(.app(appID: "noisy"), now: now) == .throttled)
        #expect(limiter.allow(.app(appID: "quiet"), now: now) == .allowed)
    }

    @Test("a flooding peer is not also a memory leak")
    func prunesOldEntries() {
        let limiter = SignalRateLimiter(limit: 5, window: 10)
        let start = Date(timeIntervalSince1970: 2000)
        for i in 0..<200 {
            _ = limiter.allow(.host, now: start.addingTimeInterval(Double(i)))
        }
        // Whatever it retains must be bounded by the window, not by history.
        #expect(limiter.recordedCount(for: .host) <= 10)
    }
}
