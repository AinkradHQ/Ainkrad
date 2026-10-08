import AinkradAppKit
import AinkradHostRuntime
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// E2.3: a theme without the island art or the sky backdrop still renders a
/// finished home, and the material pane backdrop never touches the rendered
/// image cache. Counters are per environment (the test host app runs its own).
@Suite("Home without Neon art", .serialized)
@MainActor
struct HomeWithoutNeonArtTests {
    /// No island art, and panes back onto the theme's material.
    private static let plain: [String: String] = [
        "plainhome-dark.theme": #"""
        {"schemaVersion": 1, "id": "plainhome.dark", "name": "Plain Home", "base": "neonBlue",
         "host": {"language": {"id": "plainhome", "name": "Plain Home", "appearance": "dark",
                               "islandArt": false, "paneBackdrop": "material"}}}
        """#
    ]

    private func environment(themeID: String) -> (AppEnvironment, () -> Void) {
        let t = TestHome.make("home-without-neon-art")
        ThemeFixtures.write(
            Self.plain, to: t.home.shared(.config).appendingPathComponent("Themes", isDirectory: true))
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        env.themeManager.setTheme(themeID)
        // Counters are keyed by the environment's address, which a freed one from an
        // earlier test can share; start this environment from zero.
        let id = ObjectIdentifier(env)
        PaneGlassBackdrop.debugBodyCounts[id] = nil
        PaneGlassBackdrop.debugCacheLookups[id] = nil
        PaneGlassBackdrop.debugRenders[id] = nil
        return (env, t.cleanup)
    }

    /// Hosts `view` off-screen, lets it settle, and returns a teardown.
    private func host<V: View>(_ view: V, env: AppEnvironment, size: CGSize = CGSize(width: 1000, height: 700))
        -> (NSHostingView<AnyView>, () -> Void)
    {
        let root = AnyView(
            view.environment(env)
                .ainkradSkin(env.themeManager.skin)
                .environment(\.ainkradMotionBudget, .frozen)
                .frame(width: size.width, height: size.height))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        settle(hosting)
        return (hosting, { window.contentView = nil; window.close() })
    }

    private func settle(_ hosting: NSView) {
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
    }

    @Test("the plain fixture resolves to no island art and a material backdrop")
    func fixtureResolves() {
        let (env, cleanup) = environment(themeID: "plainhome")
        defer { cleanup() }
        #expect(env.themeManager.homeLanguage.islandArt == false)
        #expect(env.themeManager.homeLanguage.paneBackdrop == .material)
        #expect(env.themeManager.homeLanguage.sky)
    }

    @Test("a material pane backdrop never looks up or renders the blurred image", arguments: ["neon", "plainhome"])
    func materialNeverTouchesImageCache(themeID: String) {
        let (env, cleanup) = environment(themeID: themeID)
        defer { cleanup() }
        let id = ObjectIdentifier(env)
        let (_, close) = host(PaneGlassBackdrop(isEnabled: true), env: env, size: CGSize(width: 320, height: 200))
        defer { close() }
        let lookups = PaneGlassBackdrop.debugCacheLookups[id, default: 0]
        if themeID == "neon" {
            #expect(lookups > 0, "control: the sky backdrop must use the cache, or the probe is broken")
        } else {
            #expect(lookups == 0, "material looked up the image cache \(lookups)x")
            #expect(PaneGlassBackdrop.debugRenders[id, default: 0] == 0)
        }
    }

    /// The measurement from `PaneGlassBackdrop`'s doc comment: five translucent,
    /// blurred panes in Focus Mode, then a tab switch. The backdrop's body must
    /// not run again, and nothing may be rendered.
    @Test("a 5-pane focus switch does not re-evaluate the pane backdrop", arguments: ["neon", "plainhome"])
    func focusSwitchSkipsBackdrop(themeID: String) throws {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let (env, cleanup) = environment(themeID: themeID)
        defer { cleanup() }
        env.appAppearanceStore.setSurfaceOpacity("hoard", 0.5)
        env.appAppearanceStore.setBlurEnabled("hoard", true)
        let workspace = env.workspaceManager.createWorkspace()
        let blocks = (0..<5).map { _ in workspace.tileLayout.openApp("hoard") }
        workspace.viewMode = .focus
        let id = ObjectIdentifier(env)

        let (hosting, close) = host(WorkspaceStack(), env: env)
        defer { close() }
        let bodies = PaneGlassBackdrop.debugBodyCounts[id, default: 0]
        let renders = PaneGlassBackdrop.debugRenders[id, default: 0]
        #expect(bodies >= 5, "control: every blurred pane evaluates its backdrop once (\(bodies))")

        workspace.tileLayout.focus(blocks[1].id)
        settle(hosting)
        workspace.tileLayout.focus(blocks[3].id)
        settle(hosting)

        #expect(workspace.tileLayout.focusedBlockID == blocks[3].id)
        #expect(PaneGlassBackdrop.debugBodyCounts[id, default: 0] == bodies)
        #expect(PaneGlassBackdrop.debugRenders[id, default: 0] == renders)
        if themeID == "plainhome" {
            #expect(PaneGlassBackdrop.debugCacheLookups[id, default: 0] == 0)
        }
    }
}
