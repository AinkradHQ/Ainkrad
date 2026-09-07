import Foundation
import CryptoKit
import AinkradSignal
import AinkradHostRuntime

/// Maps a bearer token to the `SignalSource` it may post as.
///
/// **The whole security model of the socket is here.** A wire payload never
/// names its own source (`SignalWirePayload` has no such field); the host
/// derives the source from the presented token. So a token's only job is to
/// answer "which source is this?", and a leaked token lets its holder post as
/// that source — nothing more, but nothing less either.
///
/// Consequences that are deliberately not negotiable:
///
/// - **A token never appears in a log, an error message, or the feed.** Callers
///   that need to identify a peer use `peerHash(for:)`.
/// - **Tokens are 32 bytes of `SystemRandomNumberGenerator`**, base64url
///   encoded. Not a UUID: a UUID is 122 bits with a documented structure and
///   reads as an identifier, which invites it being treated as one.
/// - **`mint` rotates.** Minting for a source that already holds a token
///   replaces it, and the old one stops resolving in the same call — a rotation
///   that leaves the previous credential working is not a rotation.
///
/// ## Why there is an index
///
/// `SecretStore` is get-by-key only — there is no enumeration — so a registry
/// cannot discover which sources hold tokens by asking the Keychain. Without a
/// record of that, nothing would resolve after a restart: the reverse map would
/// be empty and every token would read as unknown. A separate index key holds
/// the list of sources, and is written in the same operations that write and
/// clear the secrets themselves.
@MainActor
final class SignalTokenRegistry {
    private let secrets: SecretStore
    /// token → source. Built at init from the index; the authority is the
    /// secret store, this is the lookup.
    private var sourcesByToken: [String: SignalSource] = [:]

    private static let indexKey = "signal.token.index"
    private static func secretKey(for source: SignalSource) -> String? {
        Self.identifier(for: source).map { "signal.token.\($0)" }
    }

    /// A stable, filesystem- and Keychain-safe string per source. Written out
    /// by hand rather than derived from `String(describing:)`, which would
    /// change the key namespace the day the enum's cases are reordered or
    /// renamed and silently orphan every stored token.
    /// Nil for a case this build does not know. `SignalSource` is resilient
    /// (library evolution), so a newer SDK can add one; a token for a source
    /// this host cannot name has nowhere stable to live, and inventing a shared
    /// "unknown" key would let two different future sources overwrite each
    /// other's credential. Such a token works for the current launch and is
    /// simply not persisted — see `mint`.
    private static func identifier(for source: SignalSource) -> String? {
        switch source {
        case .host: return "host"
        case .sage: return "sage"
        case .app(let appID): return "app.\(appID)"
        @unknown default: return nil
        }
    }

    private static func source(fromIdentifier identifier: String) -> SignalSource? {
        switch identifier {
        case "host": return .host
        case "sage": return .sage
        default:
            guard identifier.hasPrefix("app.") else { return nil }
            let appID = String(identifier.dropFirst("app.".count))
            return appID.isEmpty ? nil : .app(appID: appID)
        }
    }

    init(secrets: SecretStore) {
        self.secrets = secrets
        for identifier in indexedIdentifiers() {
            guard let source = Self.source(fromIdentifier: identifier),
                  let token = secrets.secret(for: "signal.token.\(identifier)") else { continue }
            sourcesByToken[token] = source
        }
    }

    /// Mints a fresh token for `source`, replacing and invalidating any
    /// previous one.
    func mint(for source: SignalSource) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = generator.next() }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Drop the outgoing token from the reverse map BEFORE storing the new
        // one, so there is no instant at which both resolve.
        sourcesByToken = sourcesByToken.filter { $0.value != source }

        // Persist only a source this build can name. An unknown case still
        // gets a usable token for this launch rather than a crash or a
        // silently-shared key.
        if let key = Self.secretKey(for: source), let identifier = Self.identifier(for: source) {
            secrets.setSecret(token, for: key)
            addToIndex(identifier)
        }
        sourcesByToken[token] = source
        return token
    }

    /// The source a token may post as, or nil when the token is unknown,
    /// rotated or revoked.
    func source(for token: String) -> SignalSource? { sourcesByToken[token] }

    /// Revokes `source`'s token. Idempotent: revoking a source that holds no
    /// token is not an error.
    func revoke(_ source: SignalSource) {
        if let key = Self.secretKey(for: source), let identifier = Self.identifier(for: source) {
            secrets.setSecret(nil, for: key)
            removeFromIndex(identifier)
        }
        sourcesByToken = sourcesByToken.filter { $0.value != source }
    }

    /// A stable, non-reversible label for a peer, safe to log.
    ///
    /// Works on tokens that did NOT resolve, which is the case that matters:
    /// rejection logging exists precisely for peers presenting credentials the
    /// host does not know.
    func peerHash(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // MARK: - Index

    private func indexedIdentifiers() -> [String] {
        guard let raw = secrets.secret(for: Self.indexKey), !raw.isEmpty else { return [] }
        return raw.split(separator: "\n").map(String.init)
    }

    private func writeIndex(_ identifiers: [String]) {
        secrets.setSecret(identifiers.isEmpty ? nil : identifiers.joined(separator: "\n"),
                          for: Self.indexKey)
    }

    private func addToIndex(_ identifier: String) {
        var identifiers = indexedIdentifiers()
        guard !identifiers.contains(identifier) else { return }
        identifiers.append(identifier)
        writeIndex(identifiers)
    }

    private func removeFromIndex(_ identifier: String) {
        writeIndex(indexedIdentifiers().filter { $0 != identifier })
    }
}
