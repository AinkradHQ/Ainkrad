import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// E2.2: the home structure follows the theme's language, and a theme with
/// `sky: false` runs no sky and shows no sky settings.
@Suite("Home layout switch", .serialized)
@MainActor
struct HomeLayoutSwitchTests {
    /// A Neon-based theme with no sky (its pane backdrop resolves to material).
    private static let skyless: [String: String] = [
        "bare-dark.theme": #"""
        {"schemaVersion": 1, "id": "bare.dark", "name": "Bare", "base": "neonBlue",
         "host": {"language": {"id": "bare", "name": "Bare", "appearance": "dark", "sky": false}}}
        """#
    ]

    private func environment() -> (AppEnvironment, () -> Void) {
        let t = TestHome.make("home-layout-switch")
        ThemeFixtures.write(
            Self.skyless, to: t.home.shared(.config).appendingPathComponent("Themes", isDirectory: true))
        return (AppEnvironment.bootstrap(home: t.home, defaults: t.defaults), t.cleanup)
    }

    private func appearanceGroups(_ env: AppEnvironment) throws -> [String] {
        let page = try #require(
            HostSettingsCatalog.build(environment: env).pages.first {
                $0.path == SettingsPath(["workspace", "appearance"])
            })
        return page.groups.map(\.title)
    }

    @Test("a sky-less theme hides the Living Sky rows and switching back restores the same values")
    func skyRowsHiddenNotReset() throws {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let (env, cleanup) = environment()
        defer { cleanup() }
        let sky = env.skySettingsStore
        sky.setMotionEnabled(false)
        sky.setEnabled(false, for: .aurora)
        #expect(try appearanceGroups(env) == ["Theme", "Overlays", "Living Sky", "App Icon"])

        env.themeManager.setTheme("bare")
        #expect(env.themeManager.homeLanguage.sky == false)
        #expect(try appearanceGroups(env) == ["Theme", "Overlays", "App Icon"])
        #expect(sky.motionEnabled == false)
        #expect(sky.isEnabled(.aurora) == false)

        env.themeManager.setTheme("neon")
        #expect(try appearanceGroups(env) == ["Theme", "Overlays", "Living Sky", "App Icon"])
        #expect(sky.motionEnabled == false)
        #expect(sky.isEnabled(.aurora) == false)
        #expect(sky.isEnabled(.stars))
    }

    /// Hosts the real `WorkspaceStack` off-screen with a running motion budget
    /// and counts its sky `TimelineView`'s frame callbacks over half a second
    /// (counted per environment: the test host app's own sky ticks meanwhile).
    private func skyFrames(themeID: String) throws -> Int {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let (env, cleanup) = environment()
        defer { cleanup() }
        env.themeManager.setTheme(themeID)
        #expect(env.skySettingsStore.motionEnabled)
        let view = WorkspaceStack()
            .environment(env)
            .ainkradSkin(env.themeManager.skin)
            .environment(\.ainkradMotionBudget, .full)
            .frame(width: 640, height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        host.display()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.display()
        let frames = AmbientSkyView.debugFrameCounts[ObjectIdentifier(env), default: 0]
        window.contentView = nil
        window.close()
        return frames
    }

    @Test("the sky's TimelineView runs under Neon and never runs with sky: false")
    func skyTimelineGated() throws {
        let bare = try skyFrames(themeID: "bare")
        let neon = try skyFrames(themeID: "neon")
        #expect(neon > 0, "control: the Neon sky must tick, or the probe is broken")
        #expect(bare == 0, "sky: false ran \(bare) sky frames (Neon: \(neon))")
    }
}
