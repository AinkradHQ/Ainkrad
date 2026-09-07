import Testing
@testable import Ainkrad
import AinkradAppKit
import AinkradAppKitContract

@Suite("HostSettingsCatalog integrity")
@MainActor
struct HostSettingsCatalogIntegrityTests {
    @Test("every path in the host catalog is unique")
    func pathsUnique() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let all = catalog.pages.map(\.path)
            + catalog.pages.flatMap { $0.groups.map(\.path) }
            + catalog.allFields.map(\.path)
        #expect(Set(all).count == all.count)
    }

    @Test("every field lives under exactly one page")
    func fieldsHaveOnePage() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        for field in catalog.allFields {
            let owners = catalog.pages.filter { $0.allFields.contains { $0.path == field.path } }
            #expect(owners.count == 1, "\(field.path) is owned by \(owners.count) pages")
        }
    }

    @Test("every field path is prefixed by its group path")
    func pathsNest() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        for page in catalog.pages {
            for group in page.groups {
                #expect(group.path.segments.starts(with: page.path.segments))
                for field in group.fields {
                    #expect(field.path.segments.starts(with: group.path.segments))
                }
            }
        }
    }

    @Test("no group is empty")
    func noEmptyGroups() {
        for page in HostSettingsCatalog.build(environment: .preview()).pages {
            for group in page.groups {
                #expect(!group.fields.isEmpty, "\(group.path) has no fields")
            }
        }
    }

    @Test("the WORKSPACE pages are present and ordered")
    func workspacePages() {
        let titles = HostSettingsCatalog.build(environment: .preview())
            .pages(in: .workspace).map(\.title)
        // Notifications is last (order 5), added in M3. The pane itself was
        // built in M1 and never placed in the navigation — its delivery rules,
        // retention limits and "Clear feed" were live code with no way to
        // reach them, which is precisely what this test exists to catch and
        // could not, because an absent page breaks no expectation.
        #expect(titles == ["General", "You", "Appearance", "Sound & Voice", "Keyboard",
                           "Notifications"])
    }

    /// Every field in the live catalog must be genuinely reachable, not just
    /// present. This is the property that broke for App Icon: it was in the
    /// catalog, indexed by search, and returned as a result, but nothing
    /// could open its `collapsedByDefault` group — so a deep-link to it
    /// scrolled to nothing. `page(containing:)` resolving is necessary but
    /// not sufficient; `SettingsGroupView.mustExpand` returning true for a
    /// field highlighted inside its own collapsed group is the missing half,
    /// and it is what this test pins.
    @Test("every field in the host catalog is reachable via deep-link")
    func everyFieldIsReachable() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        var unreachable: [SettingsPath] = []

        for page in catalog.pages {
            // The field's page must actually be part of the catalog the
            // sidebar renders from (`catalog.pages`) — a page built but never
            // appended to `HostSettingsCatalog.build`'s array would be
            // unreachable regardless of what's inside it.
            guard catalog.pages.contains(where: { $0.path == page.path }) else {
                unreachable.append(page.path)
                continue
            }
            for group in page.groups {
                for field in group.fields {
                    // A deep-link must resolve to the page that owns the field.
                    guard catalog.page(containing: field.path)?.path == page.path else {
                        unreachable.append(field.path)
                        continue
                    }
                    // The group that owns the field must actually reveal it:
                    // `.always` groups never hide content, and a
                    // `.collapsedByDefault` group must open when this field
                    // is the highlighted deep-link target.
                    let revealed = group.disclosure == .always
                        || SettingsGroupView.mustExpand(
                            group: group, highlightedPath: field.path, matchedPaths: nil)
                    if !revealed {
                        unreachable.append(field.path)
                    }
                }
            }
        }

        #expect(unreachable.isEmpty, "Unreachable fields: \(unreachable.map(\.description))")
    }

    /// The composition `everyFieldIsReachable` cannot see.
    ///
    /// That test calls `SettingsGroupView.mustExpand` as a pure function, so
    /// it passes whenever a group WOULD open if asked. It never models the
    /// tab bar. But the tabbed branch of `SettingsPageView` renders exactly
    /// one group at one structural slot, and until it carried a per-group
    /// `.id` SwiftUI gave every tab's group the same view identity: the
    /// `@State isExpanded` seeded in `SettingsGroupView.init` was created once
    /// and then INHERITED by every later tab, so `mustExpand` was never
    /// consulted again. Intelligence ▸ Permissions & Sandbox has two
    /// `.collapsedByDefault` groups; collapsing the first left the second
    /// rendering as a bare header, and a deep-link into it scrolled to an id
    /// that was not in the hierarchy.
    ///
    /// `SettingsPageView.deepLinkTarget` is the composition as one pure value
    /// — (tab, group, actually expanded) — and it reasons about the same
    /// `groupViewIdentity` the view applies, so this fails if the identity
    /// ever collapses again.
    @Test("a deep-link into a collapsed group on an inactive tab resolves to that tab, open")
    func deepLinkResolvesThroughTabs() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        var broken: [String] = []

        for page in catalog.pages {
            let tabbed = SettingsPageView.usesTabs(page: page)
            for (index, group) in page.groups.enumerated() {
                for field in group.fields {
                    guard let target = SettingsPageView.deepLinkTarget(
                        page: page, highlightedPath: field.path) else {
                        broken.append("\(field.path): no target")
                        continue
                    }
                    // The right tab must be selected...
                    let expectedTab = tabbed ? index : nil
                    if target.tabIndex != expectedTab {
                        broken.append("\(field.path): tab \(String(describing: target.tabIndex)) != \(String(describing: expectedTab))")
                    }
                    if target.groupPath != group.path {
                        broken.append("\(field.path): group \(target.groupPath)")
                    }
                    // ...and the group that lands there must actually be open,
                    // INCLUDING when it is a collapsed group that was not the
                    // tab shown a moment ago.
                    if !target.groupIsExpanded {
                        broken.append("\(field.path): group renders collapsed")
                    }
                }
            }
        }

        #expect(broken.isEmpty, "Deep-links that do not land: \(broken)")
    }

    /// The concrete case from the bug report, pinned by name so a catalog
    /// edit that re-hides it reads as the regression it is.
    @Test("Permissions & Sandbox is tabbed and every collapsed tab still opens on deep-link")
    func permissionsTabsOpen() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        guard let page = catalog.pages.first(where: { $0.title.contains("Permissions") }) else {
            Issue.record("no Permissions & Sandbox page"); return
        }
        #expect(SettingsPageView.usesTabs(page: page))
        let collapsed = page.groups.enumerated().filter { $0.element.disclosure == .collapsedByDefault }
        #expect(collapsed.count >= 2, "expected more than one collapsed group behind tabs")
        for (index, group) in collapsed {
            let target = SettingsPageView.deepLinkTarget(page: page, highlightedPath: group.fields[0].path)
            #expect(target?.tabIndex == index)
            #expect(target?.groupIsExpanded == true, "\(group.path) stays collapsed on its own tab")
        }
    }

    /// App Icon must not be hidden twice. `workspace.appearance` has three
    /// groups, so it is tabbed; a `.collapsedByDefault` on top of that is the
    /// exact combination behind "I can't find the app icons settings".
    @Test("App Icon is expanded by default")
    func appIconIsAlwaysExpanded() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        guard let page = catalog.pages.first(where: { $0.path == SettingsPath(["workspace", "appearance"]) }),
              let group = page.groups.first(where: { $0.title == "App Icon" }) else {
            Issue.record("no App Icon group on workspace.appearance"); return
        }
        #expect(group.disclosure == .always)
        let target = SettingsPageView.deepLinkTarget(page: page, highlightedPath: group.fields[0].path)
        #expect(target?.groupIsExpanded == true)
    }
}
