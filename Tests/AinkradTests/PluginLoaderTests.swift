import Testing
import Foundation
import SwiftUI
@testable import Ainkrad
@testable import AinkradAppKit
import AinkradHostRuntime

/// A minimal `AinkradApp` conformance for exercising `RegisteredApp.plugin(...)`
/// directly (the loader's fixtures are binary-less, so the factory is never
/// reached end-to-end in unit tests).
private enum StubApp: AinkradApp {
    static let id = "stub"
    static let displayName = "Stub"
    static let icon = "app"
    static func makeRootView(host: HostServices) -> AnyView { AnyView(EmptyView()) }
    static func makeSettingsView(host: HostServices) -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct PluginLoaderTests {
    /// The in-memory `HostServices` the `loader()` closure builds, reused by the
    /// factory test. `declaredPresentation` here is irrelevant to what the
    /// factory test asserts (that test guards the factory's own `presentation:`
    /// argument, not the host's).
    private func stubHost(appID: String, presentation: PluginPresentation = .pane) -> HostServices {
        HostServicesImpl(
            appID: appID,
            dataRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
            secretStore: InMemorySecretStore(),
            themeManager: ThemeManager(persistence: InMemoryPersistenceStore()),
            hub: AgentContextRegistryHub(),
            actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(), signalHub: SignalEmitterHub(),
            declaredPresentation: presentation,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore())
        )
    }

    /// Writes a `.bundle` directory with a hand-authored Info.plist (no binary,
    /// so `Bundle.load()` fails after metadata passes — enough to exercise
    /// discovery, validation, and failure isolation without compiling code).
    private func writeBundle(in dir: URL, name: String, info: [String: Any]) throws {
        let bundle = dir.appendingPathComponent("\(name).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Info.plist"))
    }

    private func loader(signaturePolicy: PluginSignaturePolicy = DevModeSignaturePolicy()) -> PluginLoader {
        PluginLoader(signaturePolicy: signaturePolicy) { appID, declaredPresentation in
            self.stubHost(appID: appID, presentation: declaredPresentation)
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

    @Test("a bundle with an unsupported API version is skipped, not loaded")
    func rejectsBadAPIVersion() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info[PluginInfoKey.apiVersion] = 999
        try writeBundle(in: dir, name: "Future", info: info)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("999"))
    }

    @Test("a bundle missing a required key is skipped")
    func rejectsMissingKey() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info.removeValue(forKey: PluginInfoKey.appID)
        try writeBundle(in: dir, name: "NoID", info: info)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("metadata"))
    }

    @Test("a valid-metadata bundle with no loadable binary fails at load, isolated")
    func loadFailureIsolated() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: "Binaryless", info: validInfo)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)   // recorded, no crash
    }

    @Test("a missing directory yields no apps and no failures")
    func missingDirectory() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let result = loader().loadAll(from: [missing])
        #expect(result.apps.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test("a bundle with a path-traversal app id is skipped before load")
    func rejectsPathTraversalAppID() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info[PluginInfoKey.appID] = "../../escape"
        try writeBundle(in: dir, name: "Escape", info: info)

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("invalid app id"))
    }

    @Test("a valid-metadata bundle is skipped before load when the signature policy rejects it")
    func rejectsOnSignaturePolicy() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: "Rejected", info: validInfo)

        let result = loader(signaturePolicy: DeveloperIDSignaturePolicy()).loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("signature:"))
    }

    @Test("one bad bundle does not suppress processing of its siblings")
    func multiBundleIsolation() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var badAPI = validInfo; badAPI[PluginInfoKey.apiVersion] = 999
        try writeBundle(in: dir, name: "Future", info: badAPI)          // rejected at validation
        var noID = validInfo; noID.removeValue(forKey: PluginInfoKey.appID)
        try writeBundle(in: dir, name: "NoID", info: noID)              // rejected at metadata parse

        let result = loader().loadAll(from: [dir])
        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 2)   // BOTH processed — the scan never aborts early
    }

    // MARK: - Precedence between directories (the DevPlugins shadowing fix)

    /// Records every bundle the loader asks it about. The signature check is the
    /// last gate inside `loadBundle` before `Bundle.load()` — i.e. before the
    /// `dlopen` — so a URL absent from `seen` was never passed to `loadBundle`
    /// at all and therefore was never loaded into the process.
    ///
    /// What this proves and what it does not: it proves the loader never
    /// *entered* the load path for the shadowed bundle, which is exactly the
    /// bug (both images being `dlopen`ed, and by-name class lookup resolving to
    /// whichever was loaded first). It does not observe `dlopen` itself — the
    /// fixtures are binary-less, so no real image is ever mapped in a unit test.
    private final class RecordingSignaturePolicy: PluginSignaturePolicy, @unchecked Sendable {
        private(set) var seen: [URL] = []
        func validate(bundleURL: URL) -> Result<Void, PluginRejection> {
            seen.append(bundleURL)
            return .success(())
        }
    }

    /// Two directories, one appID: the LAST directory wins — this is the
    /// [Plugins, DevPlugins] precedence a sideloaded dev build depends on.
    @Test("the last directory's bundle wins when two directories declare the same app id")
    func lastDirectoryWinsOnDuplicateAppID() throws {
        let (release, dev) = try twoDirs()
        try writeBundle(in: release, name: "HelloRelease", info: validInfo)
        try writeBundle(in: dev, name: "HelloDev", info: validInfo)

        let policy = RecordingSignaturePolicy()
        let result = loader(signaturePolicy: policy).loadAll(from: [release, dev])

        // Binary-less fixtures cannot reach `RegisteredApp`, so the winner is
        // identified by the single load attempt that got as far as the binary.
        #expect(result.failures.count == 1)
        #expect(result.failures[0].url.lastPathComponent == "HelloDev.bundle")
        // The reason is dyld's, not a fixed string: a binary-less fixture must
        // still say something specific about WHY (see PluginLoadDiagnostics).
        #expect(!result.failures[0].reason.isEmpty)
        #expect(!result.failures[0].reason.contains("Bundle.load() failed"))
    }

    /// The shadowed release is intentionally overridden, not broken: it must not
    /// reach the user-facing "couldn't be loaded" list.
    @Test("the shadowed bundle is not reported as a failure")
    func shadowedBundleIsNotAFailure() throws {
        let (release, dev) = try twoDirs()
        try writeBundle(in: release, name: "HelloRelease", info: validInfo)
        try writeBundle(in: dev, name: "HelloDev", info: validInfo)

        let result = loader().loadAll(from: [release, dev])
        #expect(!result.failures.contains { $0.url.lastPathComponent == "HelloRelease.bundle" })
    }

    /// The regression test for the actual bug: the shadowed bundle must never be
    /// handed to `loadBundle`, because `loadBundle` is what `dlopen`s it and two
    /// images of the same plugin make class lookup resolve to the first one
    /// loaded. Asserted on a side effect of the load path, not on the returned
    /// value — the returned value looked correct even while the bug was live.
    @Test("the shadowed bundle is never entered into the load path")
    func shadowedBundleIsNeverLoaded() throws {
        let (release, dev) = try twoDirs()
        try writeBundle(in: release, name: "HelloRelease", info: validInfo)
        try writeBundle(in: dev, name: "HelloDev", info: validInfo)

        let policy = RecordingSignaturePolicy()
        _ = loader(signaturePolicy: policy).loadAll(from: [release, dev])

        #expect(policy.seen.count == 1)
        #expect(policy.seen.first?.lastPathComponent == "HelloDev.bundle")
        #expect(!policy.seen.contains { $0.lastPathComponent == "HelloRelease.bundle" })
    }

    /// Fail closed: a broken winner is reported as a failure and the shadowed
    /// bundle is NOT resurrected — silently running an older build is the whole
    /// class of bug being fixed.
    @Test("a winner that fails validation is reported and does not fall back to the shadowed bundle")
    func brokenWinnerDoesNotFallBackToShadowed() throws {
        let (release, dev) = try twoDirs()
        try writeBundle(in: release, name: "HelloRelease", info: validInfo)
        var badAPI = validInfo; badAPI[PluginInfoKey.apiVersion] = 999
        try writeBundle(in: dev, name: "HelloDev", info: badAPI)

        let policy = RecordingSignaturePolicy()
        let result = loader(signaturePolicy: policy).loadAll(from: [release, dev])

        #expect(result.apps.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].url.lastPathComponent == "HelloDev.bundle")
        #expect(result.failures[0].reason.contains("999"))
        // The shadowed release was never a fallback: it never reached the load path.
        #expect(policy.seen.isEmpty)   // the winner failed before the signature gate
    }

    /// Precedence must not collapse distinct apps: different appIDs in different
    /// directories both survive discovery and both get loaded.
    @Test("distinct app ids in different directories both load")
    func distinctAppIDsInDifferentDirectoriesBothLoad() throws {
        let (release, dev) = try twoDirs()
        try writeBundle(in: release, name: "Hello", info: validInfo)
        var other = validInfo; other[PluginInfoKey.appID] = "goodbye"
        try writeBundle(in: dev, name: "Goodbye", info: other)

        let policy = RecordingSignaturePolicy()
        let result = loader(signaturePolicy: policy).loadAll(from: [release, dev])

        #expect(policy.seen.count == 2)
        #expect(result.failures.count == 2)   // both reached the binary and both are binary-less
    }

    /// Two fresh sibling directories standing in for `Plugins` and `DevPlugins`.
    private func twoDirs() throws -> (release: URL, dev: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let release = root.appendingPathComponent("Plugins")
        let dev = root.appendingPathComponent("DevPlugins")
        for d in [release, dev] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return (release, dev)
    }

    /// Guards the value both open paths (tiling and overlay) read: the
    /// `presentation:` argument passed to `RegisteredApp.plugin(...)` must land
    /// in `RegisteredApp.presentation`. (The loader's own binary-less fixtures
    /// never reach this factory, so this is asserted directly.)
    @Test("the plugin factory propagates the declared presentation into RegisteredApp")
    func pluginFactoryPropagatesDeclaredPresentation() {
        let url = URL(fileURLWithPath: "/tmp/x")
        let overlay = RegisteredApp.plugin(
            StubApp.self, url: url, apiVersion: 4, host: stubHost(appID: "stub"), presentation: .overlay)
        #expect(overlay.presentation == .overlay)

        let pane = RegisteredApp.plugin(
            StubApp.self, url: url, apiVersion: 4, host: stubHost(appID: "stub"), presentation: .pane)
        #expect(pane.presentation == .pane)
    }
}

/// Unit tests for the message builder, which is the part of the load
/// diagnostic with real logic in it.
///
/// WHY these are error-fixture tests and not end-to-end loads: the loader's
/// fixtures are binary-less directories, so `dlopen` is never reached and a
/// genuine missing-symbol failure cannot be produced from them. The dyld text
/// below is not invented — it is copied verbatim in shape from a real
/// reproduction (a bundle linked against a dylib subsequently rebuilt without
/// the symbol), with the symbol replaced by the actual one from the 2026-07-28
/// Terminal session.
@Suite("Plugin load diagnostics")
struct PluginLoadDiagnosticsTests {

    private func loadError(debugDescription: String?) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: "The bundle “Terminal.bundle” couldn’t be loaded."]
        if let debugDescription { info[NSDebugDescriptionErrorKey] = debugDescription }
        return NSError(domain: NSCocoaErrorDomain, code: 3588, userInfo: info)
    }

    private static let skewSymbol = "_$s21AinkradAppKitContract15MCPResourceSpecV012requiresLiveB0Sbvs"

    private static let skewDyldText = """
        dlopen(/Users/x/Library/Application Support/Plugins/Terminal.bundle/Contents/MacOS/Terminal, 0x0109): Symbol not found: _$s21AinkradAppKitContract15MCPResourceSpecV012requiresLiveB0Sbvs
          Referenced from: <A> /Users/x/Library/Application Support/Plugins/Terminal.bundle/Contents/MacOS/Terminal
          Expected in:     <B> /Applications/Ainkrad.app/Contents/Frameworks/AinkradAppKit.framework/Versions/A/AinkradAppKit
        """

    @Test("SDK skew is named in plain language, with the raw symbol kept")
    func sdkSkewIsExplained() {
        let d = PluginLoadDiagnostics.diagnose(loadError(debugDescription: Self.skewDyldText))
        #expect(d.banner.contains("different AinkradAppKit revision than this host embeds"))
        #expect(d.banner.contains("repin the plugin to the host's SDK revision and rebuild"))
        #expect(d.banner.contains(Self.skewSymbol))

        // It must NOT claim which side is ahead. A missing symbol proves the two
        // disagree and nothing more — and the first real occurrence had the
        // plugins pinned BEHIND the host, so the old "newer" wording sent the
        // reader to bump the host pin, which moves it further away.
        #expect(!d.banner.lowercased().contains("newer"))
        #expect(!d.banner.lowercased().contains("older"))
        #expect(!d.banner.contains("bump the host"))

        // Fit for the banner: one line, not the three-line dyld dump.
        #expect(!d.banner.contains("\n"))
        // …but the log keeps every line of it.
        #expect(d.log == Self.skewDyldText)
        #expect(d.log.contains("Referenced from:"))
    }

    @Test("a missing symbol from some other library is reported without SDK advice")
    func nonSDKSymbolFailure() {
        let text = """
            dlopen(/tmp/P.bundle/Contents/MacOS/P, 0x0109): Symbol not found: _libgit2_thing
              Expected in:     <B> /usr/local/lib/libgit2.dylib
            """
        let d = PluginLoadDiagnostics.diagnose(loadError(debugDescription: text))
        #expect(d.banner.contains("_libgit2_thing"))
        #expect(!d.banner.contains("AinkradAppKit"))
        #expect(!d.banner.contains("\n"))
    }

    @Test("a non-symbol failure still yields its first dyld line, not a fixed string")
    func nonSymbolFailure() {
        let text = "dlopen(/tmp/P.bundle/Contents/MacOS/P, 0x0109): tried: '/tmp/P' (no such file)"
        let d = PluginLoadDiagnostics.diagnose(loadError(debugDescription: text))
        #expect(d.banner == text)
    }

    @Test("with no debug description we fall back to the localized description")
    func noDebugDescription() {
        let d = PluginLoadDiagnostics.diagnose(loadError(debugDescription: nil))
        #expect(d.banner.contains("couldn’t be loaded"))
        #expect(!d.banner.isEmpty)
    }

    @Test("the dyld text is dug out of an underlyingError when it is nested there")
    func underlyingErrorIsSearched() {
        let inner = NSError(domain: NSCocoaErrorDomain, code: 3588,
                            userInfo: [NSDebugDescriptionErrorKey: Self.skewDyldText])
        let outer = NSError(domain: NSCocoaErrorDomain, code: 3588, userInfo: [
            NSLocalizedDescriptionKey: "The bundle couldn’t be loaded.",
            NSUnderlyingErrorKey: inner,
        ])
        #expect(PluginLoadDiagnostics.diagnose(outer).banner.contains(Self.skewSymbol))
    }
}
