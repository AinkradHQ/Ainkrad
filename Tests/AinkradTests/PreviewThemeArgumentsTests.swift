import AinkradAppKit
import AinkradAppKitHome
import AppKit
import SwiftUI
import Testing

@testable import Ainkrad

/// E5.1: `AppEnvironment.preview(launchArguments:)` honours the DEBUG theme launch
/// arguments, so an off-screen snapshot can be taken under any theme and scheme.
@MainActor
@Suite("Preview theme arguments")
struct PreviewThemeArgumentsTests {
    @Test("a colour scheme argument reaches the preview's theme manager")
    func schemeArgument() {
        let env = AppEnvironment.preview(launchArguments: ["AinkradColorScheme": "dracula"])
        #expect(env.themeManager.colorSchemeID(for: env.themeManager.appearance) == "dracula")
        #expect(AppEnvironment.preview().themeManager.colorSchemeID(for: .dark) != "dracula")
    }

    /// Needs Glass's files: `make validate-themes THEMES=../AinkradCatalog/themes`.
    @Test("an off-screen snapshot under Glass differs from Neon")
    func glassSnapshot() {
        guard let dir = ProcessInfo.processInfo.environment["AINKRAD_THEMES_DIR"], !dir.isEmpty else {
            print("SKIPPED: set AINKRAD_THEMES_DIR (make validate-themes THEMES=<dir>) — no Glass snapshot was taken")
            return
        }
        let glass = AppEnvironment.preview(launchArguments: [
            "AinkradThemesDir": dir, "AinkradTheme": "glass", "AinkradAppearance": "dark",
        ])
        let neon = AppEnvironment.preview()
        #expect(glass.themeManager.currentThemeID == "glass")
        #expect(neon.themeManager.currentThemeID == "neon")

        let glassShot = snapshot(glass)
        #expect(glassShot != nil)
        #expect(glassShot != snapshot(neon))
    }

    private func snapshot(_ env: AppEnvironment) -> Data? {
        let hosting = NSHostingView(
            rootView: NeonAppTile(symbol: "folder", tokens: env.themeManager.hostSkin, size: 32)
                .frame(width: 48, height: 48)
                .environment(env)
                .ainkradSkin(env.themeManager.skin))
        hosting.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.bitmapData.map { Data(bytes: $0, count: rep.bytesPerPlane) }
    }
}
