import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Wave 0 / Blocker 1: the plugin trust boundary.
///
/// Before this, `DeveloperIDSignaturePolicy` was an always-failing stub that
/// nothing referenced, and every wiring site used `DevModeSignaturePolicy`
/// (which accepts anything). These tests pin the two properties that matter:
/// the production policy actually rejects untrusted code, and the *choice* of
/// policy is made by build configuration rather than by hand.
@Suite("Plugin trust policy")
struct PluginTrustPolicyTests {

    // MARK: - The Developer-ID requirement

    @Test("Requirement demands the Developer-ID CA and leaf markers")
    func requirementUsesDeveloperIDMarkers() {
        let text = DeveloperIDSignaturePolicy().requirementText
        // Chains to Apple, not to an arbitrary self-signed anchor.
        #expect(text.contains("anchor apple generic"))
        // Developer ID Certification Authority marker — excludes Mac App Store
        // and plain "Apple Development" certs.
        #expect(text.contains("1.2.840.113635.100.6.2.6"))
        // Developer ID Application leaf marker — excludes Developer ID Installer.
        #expect(text.contains("1.2.840.113635.100.6.1.13"))
    }

    @Test("Team pinning is opt-in and absent by default")
    func teamPinningIsOptIn() {
        // Third-party plugins ship under their OWN team, so pinning to ours by
        // default would reject the entire catalog.
        #expect(!DeveloperIDSignaturePolicy().requirementText.contains("subject.OU"))
        #expect(
            DeveloperIDSignaturePolicy(teamIdentifier: "PSY67XNHG4")
                .requirementText.contains("certificate leaf[subject.OU] = \"PSY67XNHG4\""))
        // An empty string must not produce a requirement that matches an empty OU.
        #expect(!DeveloperIDSignaturePolicy(teamIdentifier: "").requirementText.contains("subject.OU"))
    }

    // MARK: - Rejection behaviour

    @Test("Rejects a bundle that carries no code signature")
    func rejectsUnsignedBundle() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Fake.bundle")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        try "not a plist".write(
            to: dir.appendingPathComponent("Contents/Info.plist"),
            atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let result = DeveloperIDSignaturePolicy().validate(bundleURL: dir)
        guard case .failure(let rejection) = result else {
            Issue.record("unsigned bundle was accepted")
            return
        }
        // The reason is what surfaces to the user in the App Store overlay, so
        // it must be non-empty and not a bare OSStatus number.
        #expect(!rejection.reason.isEmpty)
        #expect(rejection.reason.rangeOfCharacter(from: .letters) != nil)
    }

    @Test("Rejects a path that does not exist at all")
    func rejectsMissingPath() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).bundle")
        guard case .failure = DeveloperIDSignaturePolicy().validate(bundleURL: missing) else {
            Issue.record("missing path was accepted")
            return
        }
    }

    // MARK: - Build-configuration selection

    @Test("Policy and DevPlugins scanning follow the build configuration")
    func selectionFollowsBuildConfiguration() {
        #if DEBUG
        #expect(PluginTrust.policyForCurrentBuild() is DevModeSignaturePolicy)
        #expect(PluginTrust.scansDevPluginsDirectory)
        #else
        // The whole point of Blocker 1's fix: Release cannot get the permissive
        // policy, and cannot scan the unmanaged sideload directory.
        #expect(PluginTrust.policyForCurrentBuild() is DeveloperIDSignaturePolicy)
        #expect(!PluginTrust.scansDevPluginsDirectory)
        #endif
    }
}

/// Wave 0 / RC-5: `loadFailures` was written by the loader and read by nothing,
/// which is what would have made Blocker 0 undiagnosable.
@MainActor
@Suite("Plugin load failures are surfaced")
struct PluginLoadFailureSurfacingTests {

    @Test("Store exposes the registry's load failures")
    func storeExposesFailures() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        #expect(registry.loadFailures.isEmpty)

        let failure = PluginLoadFailure(
            url: URL(fileURLWithPath: "/tmp/Plugins/Terminal.bundle"),
            reason: "signature: not signed (needs a Developer-ID signature)")
        registry.install(builtIn: [], loaded: [], failures: [failure])

        let store = AppStoreStore(service: FakeAppStoreService(), registry: registry)
        #expect(store.loadFailures == [failure])
    }

    @Test("Failure text names the bundle and the reason, not the raw path")
    func failureTextIsReadable() {
        let text = AppStoreStore.failureText(
            PluginLoadFailure(
                url: URL(fileURLWithPath: "/Users/x/Library/Application Support/Plugins/GitMage.bundle"),
                reason:
                    "was built against a different AinkradAppKit revision than this host embeds — repin the plugin to the host's SDK revision and rebuild it (missing symbol _$s21AinkradAppKitContract15MCPResourceSpecV012requiresLiveB0Sbvs)"
            ))
        #expect(text.hasPrefix("GitMage — was built against a different AinkradAppKit"))
        #expect(!text.contains("Application Support"))
        // The banner is one line: the loader's short form, never the multi-line
        // dyld dump (which goes to the log instead — see PluginLoadDiagnostics).
        #expect(!text.contains("\n"))
    }
}

/// The posture for a host that is not itself Developer-ID signed.
///
/// A host cannot coherently demand more of plugins than it can prove of
/// itself. Requiring Developer-ID plugins from an unsigned build rejects every
/// plugin and ships an app with no apps — Blocker 0 by another route.
@Suite("Trust posture follows the host's own signature")
struct HostTrustPostureTests {

    @Test("An unsigned host does not demand Developer-ID plugins")
    func unsignedHostAcceptsPlugins() {
        // The test bundle is not Developer-ID signed, so this is the real
        // answer for this process, not a stub.
        #expect(!PluginTrust.hostIsDeveloperIDSigned())
    }

    @Test("The unverified posture accepts, and is a distinct type")
    func unverifiedPolicyAccepts() {
        let url = URL(fileURLWithPath: "/tmp/anything.bundle")
        guard case .success = UnverifiedDistributionPolicy().validate(bundleURL: url) else {
            Issue.record("unverified posture rejected a bundle")
            return
        }
        // Deliberately NOT the same type as DevModeSignaturePolicy: "dev mode"
        // and "shipped with no signing identity" are different situations and
        // must be distinguishable in logs and in the UI.
        #expect(!(UnverifiedDistributionPolicy() as PluginSignaturePolicy is DevModeSignaturePolicy))
    }

    @Test("isVerifyingPluginSignatures reports the truth for this build")
    func verificationFlagMatchesPolicy() {
        let policy = PluginTrust.policyForCurrentBuild()
        #expect(PluginTrust.isVerifyingPluginSignatures == (policy is DeveloperIDSignaturePolicy))
        #if DEBUG
        // Debug is dev mode, so verification is off and the banner shows.
        #expect(!PluginTrust.isVerifyingPluginSignatures)
        #endif
    }

    @Test("A Developer-ID signed host would use the strict policy")
    func strictPolicyIsReachable() {
        // Guards the branch itself: the strict policy must still exist and
        // carry the Developer-ID requirement, so enrolling flips the posture
        // with no code change.
        #expect(DeveloperIDSignaturePolicy().requirementText.contains("1.2.840.113635.100.6.1.13"))
    }
}
