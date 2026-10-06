import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import AinkradDevHost

/// Writes a `.bundle` directory with a hand-authored Info.plist (no binary,
/// so `Bundle.load()`/the real `PluginLoader` never reach a successfully
/// loaded app on these fixtures — mirrors `PluginLoaderTests.writeBundle`,
/// copied locally since that helper isn't visible to this target).
private func writeBundle(in dir: URL, name: String, info: [String: Any]) throws {
    let bundle = dir.appendingPathComponent("\(name).bundle/Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: bundle.appendingPathComponent("Info.plist"))
}

private var validInfo: [String: Any] {
    [
        PluginInfoKey.appID: "hello",
        PluginInfoKey.displayName: "Hello",
        PluginInfoKey.iconSymbol: "hand.wave",
        PluginInfoKey.apiVersion: GenerationSupport.current,
        PluginInfoKey.principalClass: "DoesNotExist",
        "CFBundleExecutable": "hello",
    ]
}

private func stubApp(id: String = "hello") -> RegisteredApp {
    RegisteredApp(
        id: id, displayName: "Hello", icon: "hand.wave", isEnabledByDefault: true,
        source: .plugin(url: URL(fileURLWithPath: "/tmp/hello.bundle"), apiVersion: GenerationSupport.current),
        makeRootView: { AnyView(EmptyView()) },
        makeSettingsView: { AnyView(EmptyView()) },
        chromeFill: { nil })
}

@MainActor
struct DevHostModelTests {
    @Test("a valid bundle whose in-process load succeeds reaches .loaded")
    func loadsValidBundle() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: "hello", info: validInfo)
        let bundleURL = dir.appendingPathComponent("hello.bundle")

        let model = DevHostModel(loadBundle: { _ in .success(stubApp()) })
        model.load(LaunchArguments(bundleURL: bundleURL, generation: nil))

        guard case .loaded(let app) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(app.id == "hello")
    }

    @Test("a bundle built against an unsupported generation is rejected with the store range message")
    func rejectsUnsupportedGeneration() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info[PluginInfoKey.apiVersion] = 5
        try writeBundle(in: dir, name: "old", info: info)
        let bundleURL = dir.appendingPathComponent("old.bundle")

        let model = DevHostModel(loadBundle: { _ in .success(stubApp()) })
        model.load(LaunchArguments(bundleURL: bundleURL, generation: nil))

        guard case .invalid(let message) = model.state else {
            Issue.record("expected .invalid, got \(model.state)")
            return
        }
        #expect(message.contains("5"))
        #expect(message.contains("\(GenerationSupport.minSupported)"))
        #expect(message.contains("\(GenerationSupport.current)"))
    }

    @Test("a bundle missing CFBundleExecutable is rejected before load")
    func rejectsMissingExecutable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info = validInfo
        info.removeValue(forKey: "CFBundleExecutable")
        try writeBundle(in: dir, name: "noexe", info: info)
        let bundleURL = dir.appendingPathComponent("noexe.bundle")

        var loadBundleCalled = false
        let model = DevHostModel(loadBundle: { _ in
            loadBundleCalled = true
            return .success(stubApp())
        })
        model.load(LaunchArguments(bundleURL: bundleURL, generation: nil))

        guard case .invalid(let message) = model.state else {
            Issue.record("expected .invalid, got \(model.state)")
            return
        }
        #expect(message.contains("CFBundleExecutable"))
        #expect(!loadBundleCalled)
    }
}

/// A `RegisteredApp` whose two view factories record which one the Dev Host
/// asked for. Rendering `AnyView` and inspecting it is not possible, so the
/// factories themselves are the observation point — the stage picking the
/// wrong one shows up as the wrong marker, not as a view that merely looks
/// different.
@MainActor
private final class SurfaceProbe {
    var asked: [String] = []
    func app(publishesCatalog: Bool = false) -> RegisteredApp {
        var app = RegisteredApp(
            id: "hello", displayName: "Hello", icon: "hand.wave", isEnabledByDefault: true,
            source: .plugin(
                url: URL(fileURLWithPath: "/tmp/hello.bundle"),
                apiVersion: GenerationSupport.current),
            makeRootView: {
                self.asked.append("root")
                return AnyView(EmptyView())
            },
            makeSettingsView: {
                self.asked.append("settings")
                return AnyView(EmptyView())
            },
            chromeFill: { nil })
        app.settingsCatalog = {
            self.asked.append("catalog")
            guard publishesCatalog else { return nil }
            return SettingsPage(
                path: SettingsPath(["app", "hello"]), title: "Hello", icon: "hand.wave",
                group: .installedApps, order: 0, groups: [])
        }
        return app
    }
}

@MainActor
struct DevHostSettingsSurfaceTests {
    @Test("the stage renders the root view on the root surface")
    func rootSurfaceUsesRootFactory() {
        let probe = SurfaceProbe()
        _ = PluginStageView.view(for: probe.app(), surface: .root)
        #expect(probe.asked == ["root"])
    }

    @Test("the settings surface renders the app's settings catalog, not its legacy view")
    func settingsSurfaceUsesCatalog() {
        let probe = SurfaceProbe()
        _ = PluginStageView.view(for: probe.app(publishesCatalog: true), surface: .settings)
        #expect(probe.asked == ["catalog"])
    }

    @Test("an app with no settings catalog falls back to its settings view")
    func settingsSurfaceFallsBackWithoutCatalog() {
        let probe = SurfaceProbe()
        _ = PluginStageView.view(for: probe.app(), surface: .settings)
        #expect(probe.asked == ["catalog", "settings"])
    }

    @Test("a newly loaded bundle starts on the root surface")
    func loadResetsToRoot() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeBundle(in: dir, name: "hello", info: validInfo)

        let model = DevHostModel(loadBundle: { _ in .success(stubApp()) })
        model.surface = .settings
        model.load(LaunchArguments(bundleURL: dir.appendingPathComponent("hello.bundle"), generation: nil))

        #expect(model.surface == .root)
    }
}
