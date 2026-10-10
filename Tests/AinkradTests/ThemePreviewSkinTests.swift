import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

/// E5.6: each picker card previews its own theme, without changing the selection.
@MainActor
@Suite("Theme preview skins")
struct ThemePreviewSkinTests {
    private func manager(_ appearance: ThemeAppearance) -> ThemeManager {
        ThemeManager(
            persistence: InMemoryPersistenceStore(),
            catalog: ThemeCatalog(
                bundle: .main, userRoots: [ThemeFixtures.tempDir(ThemeDirectoryValidationTests.mechanism)]),
            systemAppearance: StubSystemAppearance(appearance))
    }

    @Test("a theme previews in its own skin and the selection stays")
    func ownSkin() throws {
        let m = manager(.dark)
        let mech = try #require(m.previewSkin(forTheme: "mech"))
        #expect(mech.material.kind == "glass")
        #expect(mech.id == "mechDark")
        #expect(m.activeThemeID == "neon" && m.skin.material.kind == "blur")
        #expect(m.previewSkin(forTheme: "missing") == nil)
    }

    @Test("a theme without the current appearance previews its own variant")
    func otherAppearance() throws {
        let m = manager(.light)
        m.setTheme("mech")
        #expect(m.appearance == .light)
        #expect(try #require(m.previewSkin(forTheme: "mech")).id == "mechLight")
        // Neon has no light variant: it previews its dark one.
        #expect(try #require(m.previewSkin(forTheme: "neon")).id == "neonBlue")
    }
}
