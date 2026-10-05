import Foundation
import Security

/// Dedicated error type for signature-policy failures — carries the reason
/// text that gets recorded verbatim in `PluginLoadFailure.reason`.
public struct PluginRejection: Error {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

extension PluginRejection: Equatable {}

/// Validates a bundle's code signature before the host loads its code. The
/// returned failure's reason is the text recorded for a skipped bundle.
public protocol PluginSignaturePolicy {
    func validate(bundleURL: URL) -> Result<Void, PluginRejection>
}

/// The default for un-enrolled development: accept any (incl. ad-hoc) signature,
/// logging what was accepted. NOT for production once Developer-ID lands.
public struct DevModeSignaturePolicy: PluginSignaturePolicy {
    public init() {}
    public func validate(bundleURL: URL) -> Result<Void, PluginRejection> {
        Log.registry.info("Dev-mode signature policy: accepting \(bundleURL.lastPathComponent, privacy: .public)")
        return .success(())
    }
}

/// Production policy: the bundle must carry a valid, unrevoked **Developer-ID
/// Application** signature issued by Apple.
///
/// This is the host-side replacement for the dyld library validation that
/// `config/Ainkrad.entitlements` disables (see that file). dyld's check asks
/// "same Team ID as the host", which by construction no third-party plugin can
/// satisfy; this asks the question we actually mean — "signed by an identified
/// Apple developer, and unmodified since" — and it runs *before*
/// `Bundle.load()`, so rejected code is never mapped into the process.
///
/// The requirement is the canonical Developer-ID one:
///   * `anchor apple generic` — chains to Apple's root;
///   * intermediate marker OID `1.2.840.113635.100.6.2.6` — the Developer ID CA
///     (so a Mac App Store or plain development cert does not qualify);
///   * leaf marker OID `1.2.840.113635.100.6.1.13` — Developer ID Application.
///
/// `teamIdentifier` optionally pins the leaf's OU to a single team. It is
/// deliberately `nil` by default: the whole point of the plugin catalog is that
/// third-party apps ship under *their* team.
public struct DeveloperIDSignaturePolicy: PluginSignaturePolicy {
    private let teamIdentifier: String?

    public init(teamIdentifier: String? = nil) {
        self.teamIdentifier = teamIdentifier
    }

    /// The Developer-ID Application designated requirement, optionally pinned
    /// to one team. Exposed for tests.
    public var requirementText: String {
        var text =
            "anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        if let team = teamIdentifier, !team.isEmpty {
            text += " and certificate leaf[subject.OU] = \"\(team)\""
        }
        return text
    }

    public func validate(bundleURL: URL) -> Result<Void, PluginRejection> {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            return .failure(PluginRejection(reason: Self.describe(createStatus, fallback: "bundle is not code")))
        }

        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
        guard reqStatus == errSecSuccess, let requirement else {
            // A malformed requirement is a bug in *this* file, not in the
            // plugin — fail closed rather than admitting unverified code.
            return .failure(PluginRejection(reason: "internal: bad code requirement"))
        }

        // Default flags, NOT `.enforceRevocationChecks`. This runs synchronously
        // inside `loadAll` during bootstrap; forcing revocation checks would put
        // a per-plugin network round-trip on the launch path, and a user offline
        // or behind a captive portal would launch with no apps. The system's own
        // revocation/notarization posture still applies on first run via
        // Gatekeeper; what this check must guarantee here is *authenticity and
        // integrity*, both of which are offline properties.
        let validity = SecStaticCodeCheckValidity(code, [], requirement)
        guard validity == errSecSuccess else {
            return .failure(
                PluginRejection(
                    reason: Self.describe(validity, fallback: "not signed with a valid Developer-ID identity")))
        }

        Log.registry.info("Developer-ID policy: accepted \(bundleURL.lastPathComponent, privacy: .public)")
        return .success(())
    }

    /// Turns an `OSStatus` into text a user can act on. The raw Security
    /// messages are accurate but opaque, and this string is what surfaces in
    /// the App Store overlay's "couldn't load" list.
    private static func describe(_ status: OSStatus, fallback: String) -> String {
        switch status {
        case errSecCSUnsigned:
            return "not signed (needs a Developer-ID signature)"
        case errSecCSSignatureFailed, errSecCSSignatureInvalid:
            return "signature is invalid or the bundle was modified after signing"
        case errSecCSReqFailed:
            return "signed, but not with a Developer-ID Application identity"
        case errSecCSRevokedNotarization:
            return "its signing certificate has been revoked by Apple"
        default:
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? fallback
            return "\(detail) (OSStatus \(status))"
        }
    }
}

/// The posture for a build that is not itself Developer-ID signed.
///
/// Accepts any bundle, exactly like `DevModeSignaturePolicy`, but is a
/// *distinct type* so the difference is visible in code, in logs, and to
/// `PluginTrust.isVerifyingPluginSignatures`. "Dev mode" and "shipped without
/// a signing identity" are different situations and should not share a name.
///
/// Integrity is still checked elsewhere: `PluginInstaller` verifies the
/// catalog's SHA-256 before a download is unpacked. That proves the bytes
/// match what the catalog published — not who wrote them. The honest summary
/// is: this build trusts the catalog, not the code.
public struct UnverifiedDistributionPolicy: PluginSignaturePolicy {
    public init() {}
    public func validate(bundleURL: URL) -> Result<Void, PluginRejection> {
        Log.registry.error(
            "Plugin signatures are NOT being verified: this host is not Developer-ID signed. Accepting \(bundleURL.lastPathComponent, privacy: .public)"
        )
        return .success(())
    }
}

/// Chooses the policy the host actually runs with.
///
/// This exists so the choice is made in exactly one place and cannot drift:
/// the permissive dev policy is compiled out of Release entirely, so no future
/// wiring mistake can ship it. (The audit's Blocker 1 was precisely that: a
/// correct `DeveloperIDSignaturePolicy` seam existing while every call site
/// wired `DevModeSignaturePolicy`.)
public enum PluginTrust {
    /// The policy for this build.
    ///
    /// Release builds require a Developer-ID signature on every plugin —
    /// **but only when the host itself carries one.**
    ///
    /// A host cannot coherently demand more of plugins than it can prove of
    /// itself. An unsigned or ad-hoc build is not a trusted distribution: it
    /// was not signed by an identified developer, Gatekeeper did not vet it,
    /// and anything that could replace a plugin bundle could equally replace
    /// the app binary. Demanding Developer-ID plugins there is theatre that
    /// buys no security, and it costs everything: with no Developer-ID
    /// identity available, *every* plugin is rejected and the app ships
    /// looking like it has no apps — Blocker 0 again, by a different route.
    ///
    /// So the posture follows the host's real signature, checked at runtime:
    ///
    /// * host Developer-ID signed  → require Developer-ID plugins (strict)
    /// * host unsigned or ad-hoc   → accept, and say so loudly
    ///
    /// This also means the strict posture switches itself on the day a
    /// Developer-ID release is first cut, with no code change and nothing to
    /// remember.
    public static func policyForCurrentBuild() -> PluginSignaturePolicy {
        #if DEBUG
        return DevModeSignaturePolicy()
        #else
        return hostIsDeveloperIDSigned()
            ? DeveloperIDSignaturePolicy()
            : UnverifiedDistributionPolicy()
        #endif
    }

    /// Whether plugin signatures are actually being verified in this process.
    /// Surfaced in the App Store overlay so an unverified posture is visible
    /// to the user rather than silent.
    public static var isVerifyingPluginSignatures: Bool {
        policyForCurrentBuild() is DeveloperIDSignaturePolicy
    }

    /// Whether the running host binary carries a valid Developer-ID signature.
    ///
    /// Asks the same question of ourselves that `DeveloperIDSignaturePolicy`
    /// asks of a plugin, using the same requirement.
    public static func hostIsDeveloperIDSigned() -> Bool {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return false }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(
                DeveloperIDSignaturePolicy().requirementText as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        return SecCodeCheckValidity(selfCode, [], requirement) == errSecSuccess
    }

    /// Whether the unmanaged `DevPlugins/` sideload directory is scanned.
    /// Debug-only: in Release, the only way code enters the process is an
    /// install through the catalog, which the signature policy then gates.
    public static var scansDevPluginsDirectory: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
