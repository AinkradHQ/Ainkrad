import AinkradAppKit
import AinkradAppKitHome
import AppKit
import SwiftUI
import Testing

@testable import Ainkrad

/// E2.4: the tile follows `host.language.appTile`, live, without its call sites changing.
@MainActor
@Suite("NeonAppTile")
struct NeonAppTileTests {
    @Test("a theme switch redraws the tile plain and back to Neon unchanged")
    func followsAppTileLive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = Home(vaultRoot: root.appendingPathComponent("vault"), cacheRoot: root.appendingPathComponent("cache"))
        ThemeFixtures.write(
            [
                "plaintile-dark.theme": #"""
                {"schemaVersion": 1, "id": "plaintile.dark", "name": "Plain Tile", "base": "neonBlue",
                 "host": {"language": {"id": "plaintile", "name": "Plain Tile", "appearance": "dark", "appTile": "plain"}}}
                """#
            ], to: home.shared(.config).appendingPathComponent("Themes"))
        let suite = "tile.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let env = AppEnvironment.bootstrap(
            home: home, defaults: UserDefaults(suiteName: suite)!, systemAppearance: StubSystemAppearance(.dark))

        let hosting = NSHostingView(
            rootView: NeonAppTile(symbol: "folder", tokens: env.themeManager.hostSkin, size: 32)
                .frame(width: 48, height: 48)
                .environment(env)
                .ainkradSkin(env.themeManager.skin))
        hosting.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        func snapshot() -> Data? {
            hosting.layoutSubtreeIfNeeded()
            let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
            rep.map { hosting.cacheDisplay(in: hosting.bounds, to: $0) }
            return rep?.bitmapData.map { Data(bytes: $0, count: rep!.bytesPerPlane) }
        }

        let neon = snapshot()
        env.themeManager.setTheme("plaintile")
        #expect(env.themeManager.homeLanguage.appTile == .plain)
        let plain = snapshot()
        env.themeManager.setTheme("neon")
        let neonAgain = snapshot()

        #expect(neon != nil)
        #expect(plain != neon)
        #expect(neonAgain == neon)
    }
}
