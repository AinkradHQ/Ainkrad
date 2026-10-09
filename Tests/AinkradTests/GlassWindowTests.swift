import AinkradAppKit
import AinkradHostRuntime
import AppKit
import Foundation
import Testing

@testable import Ainkrad

/// E3.2: a language with `windowGlass` makes the window clear and non-opaque;
/// every other language keeps the opaque window (a glass *material* alone does
/// not: Liquid Glass stays out of the content layer), and a live theme switch
/// re-applies it.
@Suite("Glass window", .serialized)
@MainActor
struct GlassWindowTests {
    /// Synthetic mechanism languages (not Glass's look): `pane` asks for a glass
    /// window; `liquid` has the glass material but keeps the content layer opaque.
    private static let glassLanguage: [String: String] = [
        "pane-dark.theme": #"""
        {"schemaVersion": 1, "id": "pane.dark", "name": "Pane", "base": "neonBlue",
         "material": {"kind": "glass"},
         "host": {"language": {"id": "pane", "name": "Pane", "appearance": "dark", "sky": false, "windowGlass": true}}}
        """#,
        "liquid-dark.theme": #"""
        {"schemaVersion": 1, "id": "liquid.dark", "name": "Liquid", "base": "neonBlue",
         "material": {"kind": "glass"},
         "host": {"language": {"id": "liquid", "name": "Liquid", "appearance": "dark", "paneBackdrop": "solid"}}}
        """#,
    ]

    private typealias Monitor = KeyboardShortcutMonitor.MonitoringView

    @Test("windowSurface: a glass window is clear and non-opaque; otherwise the opaque background")
    func surfacePerKind() {
        let opaque = NSColor.windowBackgroundColor
        let glass = Monitor.windowSurface(isGlass: true, opaqueBackground: opaque)
        #expect(glass.isOpaque == false)
        #expect(glass.backgroundColor == .clear)
        let solid = Monitor.windowSurface(isGlass: false, opaqueBackground: opaque)
        #expect(solid.isOpaque)
        #expect(solid.backgroundColor == opaque)
    }

    @Test("a glass material alone keeps the window opaque and panes on a solid backdrop")
    func glassMaterialKeepsContentOpaque() {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let manager = ThemeManager(
            persistence: InMemoryPersistenceStore(),
            catalog: ThemeCatalog(bundle: .main, userRoots: [ThemeFixtures.tempDir(Self.glassLanguage)]),
            systemAppearance: StubSystemAppearance(.dark))
        manager.setTheme("liquid")
        #expect(manager.skin.material.kind == "glass")
        #expect(manager.homeLanguage.windowGlass == false)
        #expect(manager.homeLanguage.paneBackdrop == .solid)
    }

    @Test("the user-root glass language composes to material.kind glass with no sky; Neon stays blur")
    func composedKind() {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let manager = ThemeManager(
            persistence: InMemoryPersistenceStore(),
            catalog: ThemeCatalog(bundle: .main, userRoots: [ThemeFixtures.tempDir(Self.glassLanguage)]),
            systemAppearance: StubSystemAppearance(.dark))
        #expect(manager.skin.material.kind == "blur")
        manager.setTheme("pane")
        #expect(manager.skin.material.kind == "glass")
        #expect(manager.homeLanguage.sky == false)
        #expect(manager.homeLanguage.windowGlass)
        let surface = Monitor.windowSurface(
            isGlass: manager.homeLanguage.windowGlass, opaqueBackground: .windowBackgroundColor)
        #expect(surface.isOpaque == false)
    }

    /// Lets the observation's main-actor hop run (as `HostServicesThemeTests`).
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("a live Neon ↔ glass switch flips a test window both ways and never leaves it stale")
    func liveSwitch() async throws {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let t = TestHome.make("glass-window")
        defer { t.cleanup() }
        ThemeFixtures.write(
            Self.glassLanguage, to: t.home.shared(.config).appendingPathComponent("Themes", isDirectory: true))
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let original = window.backgroundColor
        let monitor = Monitor()
        monitor.environment = env
        window.contentView = monitor
        defer {
            window.contentView = nil
            window.close()
        }
        #expect(window.isOpaque)

        env.themeManager.setTheme("pane")
        await settle()
        #expect(window.isOpaque == false)
        #expect(window.backgroundColor == .clear)

        env.themeManager.setTheme("neon")
        await settle()
        #expect(window.isOpaque)
        #expect(window.backgroundColor == original)

        // Re-armed after each change, not a one-shot.
        env.themeManager.setTheme("pane")
        await settle()
        #expect(window.isOpaque == false)

        // Detached: a later change leaves the window alone.
        window.contentView = nil
        env.themeManager.setTheme("neon")
        await settle()
        #expect(window.isOpaque == false)
    }
}
