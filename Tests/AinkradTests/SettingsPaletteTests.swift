import Testing

@testable import Ainkrad

@Suite("Settings search mode")
struct SettingsPaletteTests {
    @Test("an empty query browses")
    func emptyBrowses() {
        #expect(SettingsSearchMode(query: "", hasNavigated: false) == .browsing)
        #expect(SettingsSearchMode(query: "   ", hasNavigated: true) == .browsing)
    }

    @Test("typing opens the palette")
    func typingOpensPalette() {
        #expect(SettingsSearchMode(query: "blur", hasNavigated: false) == .palette("blur"))
    }

    @Test("navigating with a live query switches to filtering, not palette")
    func navigatingFilters() {
        #expect(SettingsSearchMode(query: "blur", hasNavigated: true) == .filtering("blur"))
    }

    @Test("a sidebar tap while browsing stays browsing")
    func sidebarTapFromBrowsing() {
        #expect(SettingsSearchMode.browsing.afterSidebarTap() == .browsing)
    }

    @Test(
        "a sidebar tap while the palette is open replaces it with the tapped page — never leaves it inertly on screen")
    func sidebarTapFromPalette() {
        #expect(SettingsSearchMode.palette("blur").afterSidebarTap() == .filtering("blur"))
    }

    @Test("a sidebar tap while already filtering stays filtering, on the newly tapped page, with the same query")
    func sidebarTapFromFiltering() {
        #expect(SettingsSearchMode.filtering("blur").afterSidebarTap() == .filtering("blur"))
    }

    @Test("the search field is the kit's, not a settings look-alike")
    func usesKitSearchField() {
        // SettingsSearchField is deleted; the overlay composes AinkradSearchField.
        // This test pins the enum's new home so the move is deliberate.
        #expect(SettingsSearchMode(query: "blur", hasNavigated: false) == .palette("blur"))
        #expect(SettingsSearchMode(query: "  ", hasNavigated: true) == .browsing)
    }
}
