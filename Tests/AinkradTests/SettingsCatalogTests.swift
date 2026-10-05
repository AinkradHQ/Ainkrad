import AinkradAppKitContract
import SwiftUI
import Testing

@Suite("SettingsCatalog")
@MainActor
struct SettingsCatalogTests {
    /// A tiny catalog fixture: one page, two groups, three fields.
    private func fixture() -> SettingsCatalog {
        let page = SettingsPath(["workspace", "general"])
        let visible = page.appending("visible")
        let advanced = page.appending("advanced")
        return SettingsCatalog(pages: [
            SettingsPage(
                path: page, title: "General", icon: "gearshape",
                group: .workspace, order: 0,
                groups: [
                    SettingsGroup(
                        path: visible, title: "Startup", disclosure: .always,
                        fields: [
                            SettingsField(
                                path: visible.appending("statusBar"), label: "Show status bar",
                                help: "Clock and battery in the title strip.",
                                keywords: ["clock", "battery"],
                                kind: .toggle(.constant(true))),
                            SettingsField(
                                path: visible.appending("layout"), label: "Launcher layout",
                                kind: .select(
                                    options: [SettingsOption(id: "list", title: "List")],
                                    selection: .constant("list"))),
                        ]),
                    SettingsGroup(
                        path: advanced, title: "Advanced", disclosure: .collapsedByDefault,
                        fields: [
                            SettingsField(
                                path: advanced.appending("diagnostics"), label: "Diagnostics",
                                kind: .custom(AnyView(EmptyView())), isAdvanced: true)
                        ]),
                ])
        ])
    }

    @Test("every field is reachable by its own path")
    func fieldLookup() {
        let catalog = fixture()
        let path = SettingsPath(rawValue: "workspace.general.visible.statusBar")!
        #expect(catalog.field(at: path)?.label == "Show status bar")
        #expect(catalog.page(at: SettingsPath(["workspace", "general"]))?.title == "General")
    }

    @Test("allFields flattens across groups, including custom fields")
    func flattening() {
        #expect(fixture().allFields.count == 3)
    }

    @Test("a custom field still carries searchable metadata")
    func customFieldIsIndexable() {
        let field = fixture().field(at: SettingsPath(rawValue: "workspace.general.advanced.diagnostics")!)
        #expect(field?.label == "Diagnostics")
        #expect(field?.isAdvanced == true)
    }

    @Test("every path in the catalog is unique")
    func pathsAreUnique() {
        let paths = fixture().allFields.map(\.path)
        #expect(Set(paths).count == paths.count)
    }
}
