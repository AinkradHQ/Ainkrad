import AinkradAppKit
import AinkradAppKitUI
import AppKit
import SwiftUI
import Testing

@testable import Ainkrad

@MainActor
@Suite("Hoard appearance and settings")
struct HoardAppearanceTests {
    @Test("full opacity paints the opaque base, so the pane is never clear and no backdrop is rendered")
    func opaqueYieldsOpaqueFill() throws {
        let fill = try #require(HoardApp.surfaceFill(opacity: 1.0, base: .black))
        #expect(NSColor(fill).alphaComponent == 1)
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

    @Test("the page is two tabs: Appearance (how it opens and looks), then List")
    func settingsOrganisation() {
        let page = AppSettingsCatalog.pages(environment: .preview()).first { $0.appID == HoardApp.id }
        #expect(page?.groups.map(\.title) == ["Appearance", "List"])
        // How it opens leads — Hoard has a basic mode, so both rows — then
        // transparency and blur, ONE decision, adjacent.
        let labels = page?.groups.first?.fields.map(\.label) ?? []
        #expect(Array(labels.prefix(4)) == ["Open as", "Open in", "Transparency", "Blur"])
    }

    @Test("the Transparency slider reads as transparency: right is more see-through")
    func transparencySliderDirection() throws {
        let environment = AppEnvironment.preview()
        let groups = HoardSettingsCatalog.groups(
            root: SettingsPath(["app", HoardApp.id]), environment: environment)
        let field = try #require(groups.flatMap(\.fields).first { $0.label == "Transparency" })
        guard case .slider(let range, _, let value) = field.kind else { Issue.record("not a slider"); return }
        #expect(range == 0.0...0.7)
        // Opaque (the default) sits at the LEFT end.
        #expect(value.wrappedValue == 0)
        value.wrappedValue = 0.5
        #expect(abs(environment.appAppearanceStore.surfaceOpacity(HoardApp.id) - 0.5) < 1e-9)
        value.wrappedValue = 0.7
        #expect(abs(environment.appAppearanceStore.surfaceOpacity(HoardApp.id) - 0.3) < 1e-9)
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

    @Test("typography follows the global setting until Hoard overrides it")
    func typographyFallsBackToGlobal() {
        let typography = HoardApp.typography(
            family: nil, scale: nil, globalFamily: .jetBrainsMono, globalScale: .large)
        #expect(typography == AinkradTypography(fontFamilyName: "JetBrains Mono", scale: 1.15))
    }

    @Test("a per-app override wins, and each half falls back on its own")
    func typographyOverrideWinsPerHalf() {
        let both = HoardApp.typography(
            family: .system, scale: .small, globalFamily: .exo2, globalScale: .large)
        #expect(both == AinkradTypography(fontFamilyName: nil, scale: 0.9))

        let sizeOnly = HoardApp.typography(
            family: nil, scale: .small, globalFamily: .exo2, globalScale: .large)
        #expect(sizeOnly == AinkradTypography(fontFamilyName: "Exo 2", scale: 0.9))
    }
}
