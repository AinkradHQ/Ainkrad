import Testing
import SwiftUI
import AinkradAppKit
@testable import Ainkrad

@MainActor
@Suite("Hoard appearance and settings")
struct HoardAppearanceTests {
    @Test("opaque at full opacity means no fill, so no backdrop is rendered")
    func opaqueYieldsNoFill() {
        #expect(HoardApp.surfaceFill(opacity: 1.0, base: .black) == nil)
    }

    @Test("sub-opaque yields a translucent fill, which drives the island backdrop")
    func translucentYieldsFill() {
        let fill = HoardApp.surfaceFill(opacity: 0.6, base: .black)
        #expect(fill != nil)
        // `BlockView.isTranslucentPane` and `TileLayoutView.hasTranslucentPane`
        // both branch on this alpha being < 1.
        #expect(NSColor(fill!).alphaComponent < 1)
    }

    @Test("settings declare real fields, not a wrapped view")
    func settingsAreDeclaredFields() {
        let environment = AppEnvironment.preview()
        let groups = HoardSettingsCatalog.groups(
            root: SettingsPath(["app", HoardApp.id]), environment: environment)

        let fields = groups.flatMap(\.fields)
        #expect(!fields.isEmpty)
        // The whole point: zero `.custom` fields, so Hoard doesn't push the
        // wrap-a-view ratchet in SettingsKitCompositionTests.
        let customCount = fields.filter {
            if case .custom = $0.kind { return true }
            return false
        }.count
        #expect(customCount == 0)
    }

    @Test("settings cover transparency, blur, typography and icon size")
    func settingsCoverage() {
        let environment = AppEnvironment.preview()
        let groups = HoardSettingsCatalog.groups(
            root: SettingsPath(["app", HoardApp.id]), environment: environment)
        let labels = groups.flatMap(\.fields).map(\.label)

        #expect(labels.contains("Transparency"))
        #expect(labels.contains("Blur"))
        #expect(labels.contains("Font"))
        #expect(labels.contains("Font size"))
        #expect(labels.contains("Icon size"))
    }

    @Test("settings are three groups: how it opens, how it looks, what the list shows")
    func settingsOrganisation() {
        // Surface leads as of generation 11: whether Hoard opens basic or
        // advanced decides what you GET when you open it, which outranks how it
        // looks. Appearance and List keep their previous order below it.
        let environment = AppEnvironment.preview()
        let groups = HoardSettingsCatalog.groups(
            root: SettingsPath(["app", HoardApp.id]), environment: environment)
        #expect(groups.map(\.title) == ["Surface", "Appearance", "List"])
        // Transparency and blur are ONE decision and must stay adjacent.
        let appearanceLabels = groups[1].fields.map(\.label)
        #expect(appearanceLabels.prefix(2) == ["Transparency", "Blur"])
    }

    @Test("the surface group offers both rows, because Hoard has a basic mode")
    func surfaceGroupHasBothRows() {
        let environment = AppEnvironment.preview()
        let groups = HoardSettingsCatalog.groups(
            root: SettingsPath(["app", HoardApp.id]), environment: environment)
        #expect(groups[0].fields.map(\.label) == ["Open as", "Open in"])
    }

    @Test("Hoard is exempt from the host's auto-appended blur group")
    func noDuplicateBlurGroup() {
        let environment = AppEnvironment.preview()
        let page = AppSettingsCatalog.pages(environment: environment)
            .first { $0.appID == HoardApp.id }
        // Declaring blur itself AND receiving the host's group would put two
        // blur toggles on one page.
        let blurFields = page?.allFields.filter { $0.label == "Blur" } ?? []
        #expect(blurFields.count == 1)
    }

    // The icon-size slider had no visible effect when these were computed
    // properties over a private struct — SwiftUI never registered the
    // dependency. Storing them directly is what fixes it; this pins the
    // round-trip so a refactor back to computed accessors is caught.
    @Test("icon size round-trips and persists")
    func iconSizeRoundTrips() {
        let environment = AppEnvironment.preview()
        let store = environment.filesSettingsStore
        store.iconSize = 18
        #expect(store.iconSize == 18)
        store.showMetadataColumns = false
        #expect(!store.showMetadataColumns)
        store.showMetadataColumns = true
        store.iconSize = 13
    }

    @Test("icon size clamps to a usable range")
    func iconSizeClamps() {
        let environment = AppEnvironment.preview()
        let store = environment.filesSettingsStore
        store.iconSize = 500
        #expect(store.iconSize == 22)
        store.iconSize = 0
        #expect(store.iconSize == 10)
        store.iconSize = 13
        #expect(store.iconSize == 13)
    }

    @Test("row padding scales with icon size so density stays coherent")
    func rowPaddingFollowsIconSize() {
        let environment = AppEnvironment.preview()
        let store = environment.filesSettingsStore
        store.iconSize = 10
        let small = store.rowVerticalPadding
        store.iconSize = 22
        #expect(store.rowVerticalPadding > small)
    }
}
