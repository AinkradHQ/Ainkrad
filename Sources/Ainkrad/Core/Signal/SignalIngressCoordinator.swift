import Foundation
import AinkradSignal

enum SignalIngressResult: Equatable {
    case accepted
    case rejected(SignalWireRejection)
}

/// Every policy decision for external ingress, with no socket anywhere in
/// sight: decode, authenticate, rate-limit, emit. `SignalSocketServer` only
/// moves bytes to `accept(_:)` and a reply back.
///
/// The split is the point. Policy is what there is to get wrong, and here it
/// is testable without binding a file descriptor; the socket is left with
/// almost no logic at all.
@MainActor
final class SignalIngressCoordinator {
    private let center: SignalCenter
    private let tokens: SignalTokenRegistry
    private let limiter: SignalRateLimiter

    // No suppression cache here, deliberately. Coalescing is M1's job: the
    // store collapses the same `dedupeKey` inside a 60-second window into one
    // row with a count. An in-process `Set` of reported peers was written
    // first and is worse in two ways — it suppresses FOREVER, so a problem
    // that is still happening an hour later never resurfaces, and it grows one
    // entry per distinct token, which makes a peer rotating random tokens an
    // unbounded allocation. The rate limiter already refuses to be a memory
    // leak; this must not become one instead.

    init(center: SignalCenter, tokens: SignalTokenRegistry, limiter: SignalRateLimiter) {
        self.center = center
        self.tokens = tokens
        self.limiter = limiter
    }

    /// Accepts one payload from outside the host.
    ///
    /// Order matters and is deliberate: size, then shape, then identity, then
    /// rate. The cheap checks that protect the host come before the ones that
    /// touch the credential store, so an oversized or malformed payload never
    /// causes a Keychain read.
    func accept(_ data: Data, now: Date = Date()) -> SignalIngressResult {
        let payload: SignalWirePayload
        switch SignalWire.decode(data) {
        case .success(let decoded):
            payload = decoded
        case .failure(let rejection):
            // No peer identity is available for a payload that did not decode,
            // so there is nobody to attribute a feed row to. Rejected quietly:
            // the CLI still gets the specific reason on stderr, which is where
            // a malformed payload is actually actionable.
            return .rejected(rejection)
        }

        guard let source = tokens.source(for: payload.token) else {
            reportRejection(peer: tokens.peerHash(for: payload.token))
            return .rejected(.unknownToken)
        }

        switch limiter.allow(source, now: now) {
        case .throttled:
            reportThrottle(source: source)
            return .rejected(.throttled)
        case .allowed:
            break
        }

        // The source is STAMPED from the token, never read from the payload —
        // `SignalWirePayload` has no source field to read. This line is where
        // that guarantee is cashed in.
        center.emit(SignalDraft(kind: payload.kind,
                                severity: payload.severity,
                                title: payload.title,
                                body: payload.body,
                                importance: payload.importance,
                                deepLink: payload.deepLink,
                                actions: payload.actions,
                                dedupeKey: payload.dedupeKey),
                    from: source)
        return .accepted
    }

    /// Records that someone presented a credential the host does not know.
    ///
    /// Attributed to `.host`, not to any source: the peer failed to establish
    /// one, and attributing it to a guess would put words in an innocent app's
    /// mouth. **The token never appears** — only its hash, which is the whole
    /// reason `peerHash` exists.
    private func reportRejection(peer: String) {
        center.emit(SignalDraft(kind: "signal.rejected",
                                severity: .warning,
                                title: "A program was refused access to notifications",
                                body: "It presented a credential this Mac does not recognise "
                                    + "(peer \(peer)). If you expected this, re-issue its token "
                                    + "in Settings › Notifications.",
                                // Never interrupts. A refused peer is worth
                                // recording, not worth pulling the user away
                                // for — and a toast per retry would hand an
                                // attacker the interruption they were denied.
                                importance: .background,
                                dedupeKey: "signal.rejected:\(peer)"),
                    from: .host)
    }

    /// Attributed to `.host` rather than to the throttled source, for a
    /// mechanical reason: a summary emitted AS that source would be counted
    /// against the very limit that produced it, so the one message explaining
    /// the silence would itself be silenced.
    private func reportThrottle(source: SignalSource) {
        center.emit(SignalDraft(kind: "signal.throttled",
                                severity: .info,
                                title: "\(Self.label(for: source)) is sending too many notifications",
                                body: "Some were held back to keep the feed readable.",
                                importance: .background,
                                dedupeKey: "signal.throttled:\(Self.label(for: source))"),
                    from: .host)
    }

    private static func label(for source: SignalSource) -> String {
        switch source {
        case .host: return "Ainkrad"
        case .sage: return "Sage"
        case .app(let appID): return appID
        @unknown default: return "An app"
        }
    }
}
