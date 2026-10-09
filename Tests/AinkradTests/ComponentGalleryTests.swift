import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Gallery theme injection")
@MainActor
struct ComponentGalleryTests {
    @Test("every gallery scheme maps to a HostThemeTokens the SDK can consume")
    func mapsAllThemes() {
        for theme in neonSchemeIDs {
            let t = HostThemeTokens(skin: ComponentGalleryView.skin(forScheme: theme))
            #expect(t.themeID == theme)
        }
    }

    @Test("without an app catalog the Gallery offers Neon only and composes Neon Blue")
    func neonOnlyFallback() {
        let gallery = ComponentGalleryView()
        #expect(gallery.themeOptions.map(\.id) == ["neon"])
        #expect(gallery.appearanceOptions == [.dark])
        #expect(gallery.schemeOptions.map(\.id) == ThemeManager.pickerOrdered(
            ComponentGalleryView.galleryCatalog.schemes(for: .dark)).map(\.id))
        #expect(gallery.gallerySkin.id == "neonBlue")
        // An uninstalled theme or a missing appearance falls back without trapping.
        let catalog = ComponentGalleryView.galleryCatalog
        #expect(ComponentGalleryView.skin(in: catalog, theme: "glass", appearance: .light, scheme: "glassLight").id
            == "neonBlue")
        #expect(ComponentGalleryView.skin(in: catalog, theme: "neon", appearance: .light, scheme: "nord").id
            == "neonBlue")
    }

    @Test("a user-root glass theme is listed with both appearances and its light schemes")
    func listsGlassFixture() {
        let catalog = ThemeCatalog(
            bundle: .main, userRoots: [ThemeFixtures.tempDir(ThemeDirectoryValidationTests.mechanism)])
        let gallery = ComponentGalleryView(catalog: catalog)
        #expect(gallery.themeOptions.map(\.id) == ["mech", "neon"])
        #expect(catalog.appearances(ofTheme: "mech") == [.dark, .light])
        #expect(catalog.appearances(ofTheme: "neon") == [.dark])
        #expect(catalog.schemes(for: .light).map(\.id) == ["mechLight"])

        let light = ComponentGalleryView.skin(in: catalog, theme: "mech", appearance: .light, scheme: "mechLight")
        #expect(light.id == "mechLight")
        #expect(light.material.kind == "glass")
        // An unknown scheme falls back to the variant's own scheme.
        #expect(ComponentGalleryView.skin(in: catalog, theme: "mech", appearance: .light, scheme: "nope").id
            == "mechLight")
        #expect(ComponentGalleryView.skin(in: catalog, theme: "mech", appearance: .dark, scheme: "nord").id == "nord")
    }

    @Test("previewing Glass in the Gallery leaves the app's ThemeManager and settings untouched")
    func subtreeOverrideLeavesThemeManager() {
        let store = InMemoryPersistenceStore()
        let catalog = ThemeCatalog(
            bundle: .main, userRoots: [ThemeFixtures.tempDir(ThemeDirectoryValidationTests.mechanism)])
        let manager = ThemeManager(persistence: store, catalog: catalog, systemAppearance: StubSystemAppearance(.dark))
        let before = (manager.currentThemeID, manager.composedKey, manager.skin.id, manager.appearance)

        let gallery = ComponentGalleryView(catalog: manager.catalog, theme: "mech", appearance: .light)
        #expect(gallery.galleryTheme == "mechLight")
        #expect(gallery.schemeOptions.map(\.id) == ["mechLight"])
        #expect(gallery.gallerySkin.material.kind == "glass")

        #expect(manager.currentThemeID == before.0)
        #expect(manager.composedKey == before.1)
        #expect(manager.skin.id == before.2)
        #expect(manager.appearance == before.3)
        #expect(manager.skin.id == "neonBlue")
        #expect(store.load(GlobalSettings.self) == nil)
    }
}
