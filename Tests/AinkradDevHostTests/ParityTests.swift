import Testing
import Foundation
import SwiftUI
@testable import AinkradDevHost
import AinkradAppKit
import AinkradHostRuntime

/// Proves the Dev Host's entire reason for existing: `DevHostModel.load`
/// produces the SAME verdict and rejection message as the real host's
/// `PluginLoader` for the same bundle, because both go through the shared
/// `AinkradHostRuntime.PluginValidator` (-> `AinkradAppKit.PluginValidation`).
///
/// Each row drives TWO independent computations over the identical fixture:
///   1. `PluginLoader.loadBundle(at:)` — what the real host / store review sees.
///   2. `DevHostModel.load` — which runs its OWN call to `PluginValidator`
///      before ever touching the injected load step, then (only on a
///      validation pass) delegates to the injected `loadBundle` closure,
///      here wired to that SAME `PluginLoader` instance so the loaded path
///      is identical too.
/// The model never reads the host's rejection text directly, so an exact
/// string match below is only possible because both paths call through the
/// same shared validator with the same inputs — a genuine parity proof, not
/// a tautology. If the Dev Host ever reimplemented validation instead of
/// sharing it, these assertions would immediately start failing on message
/// drift.
@MainActor
struct ParityTests {
    /// Mirrors `PluginLoaderTests.writeBundle` / `stubHost` — copied locally
    /// since those helpers aren't visible to this target.
    private func writeBundle(in dir: URL, name: String, info: [String: Any]) throws {
        let bundle = dir.appendingPathComponent("\(name).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Info.plist"))
    }

    private func stubHost(appID: String, presentation: PluginPresentation = .pane) -> HostServices {
        HostServicesImpl(
            appID: appID,
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: AgentContextRegistryHub(),
            actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(),
            signalHub: SignalEmitterHub(),
            declaredPresentation: presentation,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore())
        )
    }

    /// Builds a real `PluginLoader`, configured with the SAME
    /// `minSupportedAPIVersion` floor `DevHostModel.load` uses by default
    /// (`args.generation == nil` -> `AinkradAppKit.apiVersion`), so the two
    /// computations below are comparing like configurations, not exploiting
    /// a coincidence between `GenerationSupport.minSupported` and `current`.
    private func hostLoader() -> PluginLoader {
        // `GenerationSupport.minSupported`, because that is what the SHIPPING
        // host passes (`AppEnvironment.bootstrapCoreStores`). Pinning this
        // stand-in to `apiVersion` gave the parity suite a host that rejects
        // the previous generation, so it agreed with a Dev Host making the same
        // mistake and the pair looked consistent while both were wrong. A
        // parity test is only worth having if one side is the real thing.
        PluginLoader(signaturePolicy: DevModeSignaturePolicy(),
                     minSupportedAPIVersion: GenerationSupport.minSupported) { appID, presentation in
            self.stubHost(appID: appID, presentation: presentation)
        }
    }

    private var validInfo: [String: Any] {
        [
            PluginInfoKey.appID: "hello",
            PluginInfoKey.displayName: "Hello",
            PluginInfoKey.iconSymbol: "hand.wave",
            PluginInfoKey.apiVersion: AinkradAppKit.apiVersion,
            PluginInfoKey.principalClass: "DoesNotExist",
            "CFBundleExecutable": "hello",
        ]
    }

    private func makeBundle(name: String, info: [String: Any]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: name, info: info)
        return dir.appendingPathComponent("\(name).bundle")
    }

    /// A fixture that passes ALL of shared validation (app id, executable
    /// key, API-version range) and only fails at the in-process `Bundle
    /// .load()` step, because these binary-less fixtures carry no real
    /// executable (see `PluginLoaderTests.loadFailureIsolated`). Parity here
    /// proves validation genuinely runs to completion identically on both
    /// paths, not merely that both reject early for the same trivial reason.
    @Test("a validation-passing bundle: host and Dev Host agree it reaches the same load-step failure")
    func validBundleAgreesPastValidation() throws {
        let url = try makeBundle(name: "hello", info: validInfo)
        let loader = hostLoader()

        let hostResult = loader.loadBundle(at: url)
        guard case .failure(let hostRejection) = hostResult else {
            Issue.record("expected the host loader to fail at Bundle.load() on a binary-less fixture")
            return
        }
        // Prove the fixture reaches the load step by asserting validation
        // ACCEPTS it, rather than pattern-matching the failure text.
        //
        // This used to pin the literal "Bundle.load() failed", which stopped
        // being produced when `PluginLoadDiagnostics` began surfacing dyld's
        // own message. Nothing noticed, because this target was not wired into
        // `make test`. Matching on the message was always the wrong axis: the
        // banner is a diagnostic for humans and is free to improve.
        let info = try #require(Bundle(url: url)?.infoDictionary)
        let metadata = try #require(try? PluginBundleMetadata.parse(infoDictionary: info).get())
        #expect(throws: Never.self) {
            try PluginValidator.validate(
                metadata, infoDictionary: info,
                minSupportedAPIVersion: AinkradAppKit.apiVersion).get()
        }
        #expect(!hostRejection.reason.isEmpty)

        let model = DevHostModel(loadBundle: loader.loadBundle)
        model.load(LaunchArguments(bundleURL: url, generation: nil))

        guard case .invalid(let message) = model.state else {
            Issue.record("expected .invalid, got \(model.state)")
            return
        }
        #expect(message == hostRejection.reason)
    }

    @Test("an out-of-range generation: host and Dev Host reject with the identical range message")
    func outOfRangeGenerationAgrees() throws {
        var info = validInfo
        info[PluginInfoKey.apiVersion] = 999
        let url = try makeBundle(name: "future", info: info)
        let loader = hostLoader()

        let hostResult = loader.loadBundle(at: url)
        guard case .failure(let hostRejection) = hostResult else {
            Issue.record("expected the host loader to reject an out-of-range API version")
            return
        }
        #expect(hostRejection.reason.contains("999"))

        let model = DevHostModel(loadBundle: loader.loadBundle)
        model.load(LaunchArguments(bundleURL: url, generation: nil))

        guard case .invalid(let message) = model.state else {
            Issue.record("expected .invalid, got \(model.state)")
            return
        }
        #expect(message == hostRejection.reason)
    }

    @Test("a missing CFBundleExecutable: host and Dev Host reject with the identical message")
    func missingExecutableAgrees() throws {
        var info = validInfo
        info.removeValue(forKey: "CFBundleExecutable")
        let url = try makeBundle(name: "noexe", info: info)
        let loader = hostLoader()

        let hostResult = loader.loadBundle(at: url)
        guard case .failure(let hostRejection) = hostResult else {
            Issue.record("expected the host loader to reject a missing CFBundleExecutable")
            return
        }
        #expect(hostRejection.reason == "missing CFBundleExecutable")

        let model = DevHostModel(loadBundle: loader.loadBundle)
        model.load(LaunchArguments(bundleURL: url, generation: nil))

        guard case .invalid(let message) = model.state else {
            Issue.record("expected .invalid, got \(model.state)")
            return
        }
        #expect(message == hostRejection.reason)
    }
}
