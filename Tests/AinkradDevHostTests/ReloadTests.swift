import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import AinkradDevHost

/// Proves the CLI's rebuild -> relaunch loop actually picks up the FRESH
/// bundle rather than replaying a stale cached result. A real relaunch is a
/// fresh process calling `DevHostModel.load` once with `LaunchArguments`
/// parsed from argv; this simulates that by reusing one long-lived
/// `DevHostModel` (a strictly harder bar than a fresh process would need to
/// clear: if anything anywhere cached the first load, the second call here
/// would still surface it) and calling `load` twice with launch arguments
/// pointing at the rebuilt output — exactly what happens across a real
/// relaunch, whose fresh process gets fresh `--bundle` argv from the CLI.
///
/// The two builds live at DISTINCT paths (a fresh output directory per
/// "build", as `xcodebuild`'s DerivedData naturally produces) rather than
/// overwriting one path in place: `Foundation.Bundle` caches an
/// `NSBundle`/`Info.plist` by URL for the lifetime of the process, so
/// rewriting the SAME path in-process and re-reading it would test Bundle's
/// cache, not `DevHostModel`'s freshness — and would fail even for a
/// perfectly-correct model. A real relaunch never hits that cache because
/// it is a brand-new process. Pointing `load` at the new build's own path is
/// the documented alternative in the task brief and sidesteps the artifact
/// entirely.
@MainActor
struct ReloadTests {
    private func writeBundle(in dir: URL, name: String, info: [String: Any]) throws {
        let bundle = dir.appendingPathComponent("\(name).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Info.plist"))
    }

    private func info(displayName: String) -> [String: Any] {
        [
            PluginInfoKey.appID: "hello",
            PluginInfoKey.displayName: displayName,
            PluginInfoKey.iconSymbol: "hand.wave",
            PluginInfoKey.apiVersion: AinkradAppKit.apiVersion,
            PluginInfoKey.principalClass: "DoesNotExist",
            "CFBundleExecutable": "hello",
        ]
    }

    /// Stands in for the real `PluginLoader`'s in-process load step, but
    /// reads the bundle's CURRENT `Info.plist` off disk on every call (as the
    /// real loader would, via `Bundle(url:).infoDictionary`) instead of
    /// returning a value captured once at closure-creation time. This is
    /// what makes the assertion below able to fail: if `DevHostModel` ever
    /// cached the first `RegisteredApp` and skipped re-reading on a later
    /// `load` call, this closure's fresh-disk-read would be bypassed and the
    /// test would see the stale "v1" marker.
    private func freshReadingLoadBundle(_ url: URL) -> Result<RegisteredApp, PluginRejection> {
        guard let bundle = Bundle(url: url),
            let plist = bundle.infoDictionary,
            let marker = plist[PluginInfoKey.displayName] as? String
        else {
            return .failure(PluginRejection(reason: "missing Info.plist"))
        }
        return .success(
            RegisteredApp(
                id: "hello", displayName: marker, icon: "hand.wave", isEnabledByDefault: true,
                source: .plugin(url: url, apiVersion: AinkradAppKit.apiVersion),
                makeRootView: { AnyView(EmptyView()) },
                makeSettingsView: { AnyView(EmptyView()) },
                chromeFill: { nil }))
    }

    @Test("relaunching against a rebuilt bundle loads the NEW version marker, not the stale one")
    func reloadPicksUpRebuiltBundle() throws {
        let model = DevHostModel(loadBundle: freshReadingLoadBundle)

        // First launch: the developer's initial build, marked "v1", at its
        // own build-output directory.
        let dir1 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try writeBundle(in: dir1, name: "hello", info: info(displayName: "v1"))
        let args1 = LaunchArguments(bundleURL: dir1.appendingPathComponent("hello.bundle"), generation: nil)

        model.load(args1)

        guard case .loaded(let firstApp) = model.state else {
            Issue.record("expected .loaded after the first launch, got \(model.state)")
            return
        }
        #expect(firstApp.displayName == "v1")

        // Simulate `xcodebuild` producing a rebuilt output, marked "v2", at
        // a fresh build directory, then the CLI relaunching the Dev Host
        // with launch arguments pointing at THAT output — exactly what a
        // fresh process's `--bundle` argv would carry after a rebuild.
        let dir2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        try writeBundle(in: dir2, name: "hello", info: info(displayName: "v2"))
        let args2 = LaunchArguments(bundleURL: dir2.appendingPathComponent("hello.bundle"), generation: nil)

        model.load(args2)

        guard case .loaded(let secondApp) = model.state else {
            Issue.record("expected .loaded after the rebuild+relaunch, got \(model.state)")
            return
        }
        // The crux: this must be "v2", not the first launch's "v1". A model
        // that cached the first `RegisteredApp` (or a `loadBundle` seam that
        // captured the marker instead of re-reading disk) would fail here by
        // still reporting "v1".
        #expect(secondApp.displayName == "v2")
        #expect(secondApp.displayName != firstApp.displayName)
    }
}
