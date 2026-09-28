import SwiftUI
import Testing
@testable import Ainkrad
import AinkradAppKitContract
import AinkradHostRuntime

@Suite("App settings pages")
@MainActor
struct AppSettingsCatalogTests {
    @Test("an app that publishes no catalog still gets a page wrapping its view, findable by name")
    func fallbackPage() {
        let environment = AppEnvironment.preview()
        let pages = AppSettingsCatalog.pages(environment: environment)
        #expect(!pages.isEmpty)
        for page in pages {
            #expect(page.appID != nil)
            #expect(!page.groups.isEmpty)

            // None of the preview environment's apps publish a catalog, so
            // every page here goes through the fallback path. The fallback
            // field is the entire searchability guarantee for a
            // non-adopting plugin: it must be `.custom` (wrapping the app's
            // own `makeSettingsView`) and must carry the app's display name
            // as a keyword, or the app becomes unfindable in search.
            guard let appID = page.appID,
                  let app = environment.registry.allApps.first(where: { $0.id == appID }),
                  app.settingsCatalog() == nil
            else { continue }

            let field = page.groups.first { $0.title == page.title }?.fields.first
            #expect(field != nil, "\(page.title) has no fallback field")
            if let field {
                if case .custom = field.kind {
                    // expected
                } else {
                    Issue.record("\(page.title)'s fallback field is not .custom")
                }
                #expect(field.keywords.contains(page.title.lowercased()),
                        "\(page.title)'s fallback field is missing its own name as a keyword")
            }
        }
    }

    @Test("every app page carries the host appearance group as a normal group")
    func appearanceGroupIsNormal() {
        let pages = AppSettingsCatalog.pages(environment: .preview())
            .filter { $0.appID != SageApp.id }
        for page in pages {
            #expect(page.groups.contains { $0.title == "Appearance" },
                    "\(page.title) is missing the host appearance group")
        }
    }

    @Test("Appearance is the first tab, and no page keeps a separate Surface tab")
    func appearanceLeadsAndSurfaceIsMerged() {
        for page in AppSettingsCatalog.pages(environment: .preview()) where page.appID != SageApp.id {
            #expect(page.groups.first?.title == "Appearance", "\(page.title) does not open on Appearance")
            #expect(!page.groups.contains { $0.title == "Surface" }, "\(page.title) still has a Surface tab")
            #expect(page.groups.filter { $0.title == "Appearance" }.count == 1,
                    "\(page.title) has more than one Appearance tab")
        }
    }

    @Test("built-in and installed apps land in different sidebar groups")
    func groupSplit() {
        let pages = AppSettingsCatalog.pages(environment: .preview())
        #expect(pages.allSatisfy { $0.group == .builtInApps || $0.group == .installedApps })
    }

    @Test("a plugin's hostile paths are re-rooted under its own namespace, never a host or another app's page")
    func hostilePathsAreNamespaced() {
        let environment = AppEnvironment.preview()

        // A real host page path, and a real other-app path (the built-in
        // Sage's page root), copy-pasted or deliberately collided with
        // by a hostile plugin.
        let hostPath = SettingsPath(["workspace", "general"])
        let otherAppPath = SettingsPath(["app", SageApp.id])

        var hostile = RegisteredApp(
            id: "hostile-plugin",
            displayName: "Hostile Plugin",
            icon: "ant",
            isEnabledByDefault: true,
            source: .plugin(url: URL(string: "https://example.com/hostile")!, apiVersion: 1),
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        hostile.settingsCatalog = {
            SettingsPage(
                path: SettingsPath(["app", "hostile-plugin"]),
                title: "Hostile Plugin", icon: "ant",
                group: .installedApps, order: 0,
                groups: [
                    SettingsGroup(path: hostPath, title: "Steal host", fields: [
                        SettingsField(path: hostPath.appending("evil"), label: "Evil",
                                      kind: .toggle(.constant(false)))
                    ]),
                    SettingsGroup(path: otherAppPath, title: "Steal other app", fields: [
                        SettingsField(path: otherAppPath.appending("evil"), label: "Evil too",
                                      kind: .toggle(.constant(false)))
                    ])
                ],
                appID: "hostile-plugin")
        }
        environment.registry.register(hostile)

        let catalog = HostSettingsCatalog.build(environment: environment)

        // The host's own page at its own path is untouched.
        let hostPage = catalog.page(at: hostPath)
        #expect(hostPage != nil)
        #expect(hostPage?.title == "General")
        #expect(hostPage?.appID == nil)

        // The other app's page at its own path is untouched.
        let assistantPage = catalog.page(at: otherAppPath)
        #expect(assistantPage != nil)
        #expect(assistantPage?.appID == SageApp.id)

        // The hostile plugin's own page carries no group/field path outside
        // its own ["app", "hostile-plugin", ...] namespace.
        let hostilePage = catalog.pages.first { $0.appID == "hostile-plugin" }
        #expect(hostilePage != nil)
        for group in hostilePage?.groups ?? [] {
            #expect(group.path.segments.starts(with: ["app", "hostile-plugin"]),
                    "group path \(group.path) escaped the plugin's namespace")
            for field in group.fields {
                #expect(field.path.segments.starts(with: ["app", "hostile-plugin"]),
                        "field path \(field.path) escaped the plugin's namespace")
            }
        }
    }
}
