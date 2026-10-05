import AinkradAppKitContract
import Testing

@testable import Ainkrad

@Suite("SettingsNavigator")
@MainActor
struct SettingsNavigatorTests {
    @Test("navigating to a field selects its page and highlights the field")
    func navigateToField() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let field = catalog.allFields[0]
        let navigator = SettingsNavigator(initial: SettingsPath(["workspace", "general"]))

        navigator.navigate(to: field.path, in: catalog)

        #expect(navigator.selection == catalog.page(containing: field.path)?.path)
        #expect(navigator.highlightedPath == field.path)
    }

    @Test("navigating to a page selects it and highlights nothing")
    func navigateToPage() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let page = catalog.pages(in: .workspace)[1]
        let navigator = SettingsNavigator(initial: SettingsPath(["workspace", "general"]))

        navigator.navigate(to: page.path, in: catalog)

        #expect(navigator.selection == page.path)
        #expect(navigator.highlightedPath == nil)
    }

    @Test("an unknown path leaves the selection untouched")
    func unknownPathIsIgnored() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let navigator = SettingsNavigator(initial: SettingsPath(["workspace", "general"]))

        navigator.navigate(to: SettingsPath(["nope", "missing"]), in: catalog)

        #expect(navigator.selection == SettingsPath(["workspace", "general"]))
    }
}
