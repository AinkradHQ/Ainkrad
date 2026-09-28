import Testing
import SwiftUI
import AinkradAppKit
import AinkradAppKitContract

@Suite("SettingsPageView")
@MainActor
struct SettingsPageViewTests {
    private func page(groupCount: Int) -> SettingsPage {
        let root = SettingsPath(["test", "page"])
        return SettingsPage(
            path: root, title: "Test", icon: "gear", group: .workspace, order: 0,
            groups: (0..<groupCount).map { i in
                SettingsGroup(path: root.appending("g\(i)"), title: "Group \(i)", fields: [
                    SettingsField(path: root.appending("g\(i)").appending("f"),
                                  label: "Field", kind: .toggle(.constant(false)))
                ])
            })
    }

    @Test("the mini-map needs both four groups and enough width")
    func miniMapVisibility() {
        #expect(!SettingsPageView.showsMiniMap(page: page(groupCount: 3), width: 1000))
        #expect(!SettingsPageView.showsMiniMap(page: page(groupCount: 4), width: 600))
        #expect(SettingsPageView.showsMiniMap(page: page(groupCount: 4), width: 1000))
    }

    @Test("filtering dims rather than removes — every field still renders")
    func filterIsNonDestructive() {
        let p = page(groupCount: 2)
        let matched: Set<SettingsPath> = [p.groups[0].fields[0].path]
        #expect(SettingsGroupView.opacity(for: p.groups[1].fields[0].path, matchedPaths: matched) == 0.35)
        #expect(SettingsGroupView.opacity(for: p.groups[0].fields[0].path, matchedPaths: matched) == 1.0)
        #expect(SettingsGroupView.opacity(for: p.groups[1].fields[0].path, matchedPaths: nil) == 1.0)
    }

    @Test("a group's hit count counts only its own matches")
    func hitCounts() {
        let p = page(groupCount: 2)
        let matched: Set<SettingsPath> = [p.groups[0].fields[0].path]
        #expect(SettingsGroupView.hitCount(group: p.groups[0], matchedPaths: matched) == 1)
        #expect(SettingsGroupView.hitCount(group: p.groups[1], matchedPaths: matched) == 0)
    }

    private func pane(_ path: SettingsPath) -> SettingsField {
        SettingsField(path: path, label: "Pane", kind: .custom(AnyView(EmptyView())))
    }

    private func control(_ path: SettingsPath) -> SettingsField {
        SettingsField(path: path, label: "Control", kind: .toggle(.constant(false)))
    }

    @Test("a group is pane-only when every field in it is a pane")
    func paneOnlyDetection() {
        let g = SettingsPath(["p", "g"])
        #expect(SettingsGroupView.isPaneOnly(
            SettingsGroup(path: g, title: "G", fields: [pane(g.appending("a")), pane(g.appending("b"))])))
        #expect(!SettingsGroupView.isPaneOnly(
            SettingsGroup(path: g, title: "G", fields: [pane(g.appending("a")), control(g.appending("b"))])))
        #expect(!SettingsGroupView.isPaneOnly(
            SettingsGroup(path: g, title: "G", fields: [control(g.appending("a"))])))
        // An empty group is not "pane-only" — suppressing its header would
        // leave nothing at all on screen for it.
        #expect(!SettingsGroupView.isPaneOnly(SettingsGroup(path: g, title: "G", fields: [])))
    }

    @Test("the catalog's group header is suppressed only for an always-expanded pane-only group")
    func headerSuppression() {
        let g = SettingsPath(["p", "g"])
        // Pane-only + always expanded: the pane draws its own heading, so the
        // catalog's would be the second one on the page.
        #expect(!SettingsGroupView.showsHeader(for:
            SettingsGroup(path: g, title: "G", fields: [pane(g.appending("a"))])))

        // Collapsible: the header IS the disclosure control — never suppressed,
        // or the group could not be opened.
        #expect(SettingsGroupView.showsHeader(for:
            SettingsGroup(path: g, title: "G", disclosure: .collapsedByDefault,
                          fields: [pane(g.appending("a"))])))

        // Any real control in the group means real rows, which have no heading
        // of their own and need the group's.
        #expect(SettingsGroupView.showsHeader(for:
            SettingsGroup(path: g, title: "G", fields: [control(g.appending("a"))])))
        #expect(SettingsGroupView.showsHeader(for:
            SettingsGroup(path: g, title: "G",
                          fields: [pane(g.appending("a")), control(g.appending("b"))])))
    }

    @Test("an always-expanded group composes AinkradSectionFrame")
    func alwaysGroupUsesSectionFrame() {
        let root = SettingsPath(["test", "page"])
        let group = SettingsGroup(path: root.appending("g"), title: "Startup",
                                  disclosure: .always, fields: [
            SettingsField(path: root.appending("g").appending("f"),
                          label: "Field", kind: .toggle(.constant(false)))
        ])
        let described = String(describing: SettingsGroupView(group: group, layout: .stacked).body)
        #expect(described.contains("AinkradSectionFrame"))
    }

    @Test("a collapsed-by-default group composes AinkradDisclosureGroup")
    func collapsibleGroupUsesDisclosure() {
        let root = SettingsPath(["test", "page"])
        let group = SettingsGroup(path: root.appending("g"), title: "Advanced",
                                  disclosure: .collapsedByDefault, fields: [
            SettingsField(path: root.appending("g").appending("f"),
                          label: "Field", kind: .toggle(.constant(false)))
        ])
        let described = String(describing: SettingsGroupView(group: group, layout: .stacked).body)
        #expect(described.contains("AinkradDisclosureGroup"))
    }

    @Test("a group containing the highlighted path must expand")
    func mustExpandForHighlightedPath() {
        let g = SettingsPath(["p", "g"])
        let target = g.appending("f")
        let group = SettingsGroup(path: g, title: "G", disclosure: .collapsedByDefault,
                                  fields: [control(target)])
        #expect(SettingsGroupView.mustExpand(group: group, highlightedPath: target, matchedPaths: nil))
        // A highlight for a path outside the group must not force it open.
        #expect(!SettingsGroupView.mustExpand(
            group: group, highlightedPath: SettingsPath(["other", "path"]), matchedPaths: nil))
        // No highlight, no filter: stays closed.
        #expect(!SettingsGroupView.mustExpand(group: group, highlightedPath: nil, matchedPaths: nil))
    }

    @Test("a group containing a filter match must expand")
    func mustExpandForFilterMatch() {
        let g = SettingsPath(["p", "g"])
        let target = g.appending("f")
        let group = SettingsGroup(path: g, title: "G", disclosure: .collapsedByDefault,
                                  fields: [control(target)])
        #expect(SettingsGroupView.mustExpand(group: group, highlightedPath: nil, matchedPaths: [target]))
        // A match elsewhere doesn't force this group open.
        #expect(!SettingsGroupView.mustExpand(
            group: group, highlightedPath: nil, matchedPaths: [SettingsPath(["other", "path"])]))
        // `matchedPaths == nil` means no active filter — never forces open on that basis alone.
        #expect(!SettingsGroupView.mustExpand(group: group, highlightedPath: nil, matchedPaths: nil))
    }

    @Test("row width accounts for the mini-map's occupied space, not just total width")
    func rowAreaWidthSubtractsMiniMap() {
        let p = page(groupCount: 4)
        // Total width is comfortably past the wide breakpoint (900), but once
        // the mini-map's ~168pt is subtracted the rows don't actually have
        // side-by-side room. If the mini-map's width were ignored, this would
        // report a width still >= wideBreakpoint and pick .sideBySide.
        let total: CGFloat = 950
        let rowWidth = SettingsPageView.rowAreaWidth(page: p, totalWidth: total)
        #expect(rowWidth == total - SettingsPageView.miniMapOccupiedWidth)
        #expect(SettingsRowLayout(detailWidth: rowWidth) == .stacked)

        // No mini-map (too few groups) — the full width is available to rows.
        let noMiniMap = page(groupCount: 3)
        #expect(SettingsPageView.rowAreaWidth(page: noMiniMap, totalWidth: total) == total)
    }

    /// Two since AppKit #48: an app page with Appearance plus one tab of its
    /// own was a stacked scroll beside tabbed neighbours.
    @Test("tabs appear for any page with two or more groups")
    func tabsForMultiGroupPages() {
        #expect(!SettingsPageView.usesTabs(page: page(groupCount: 1)))
        #expect(SettingsPageView.usesTabs(page: page(groupCount: 2)))
        #expect(SettingsPageView.usesTabs(page: page(groupCount: 3)))
        #expect(SettingsPageView.usesTabs(page: page(groupCount: 4)))
    }

    @Test("a tab reports how many of its own fields match the filter")
    func tabHitCounts() {
        let p = page(groupCount: 3)
        let matched: Set<SettingsPath> = [p.groups[1].fields[0].path]
        #expect(SettingsPageView.tabHitCount(group: p.groups[0], matchedPaths: matched) == 0)
        #expect(SettingsPageView.tabHitCount(group: p.groups[1], matchedPaths: matched) == 1)
        #expect(SettingsPageView.tabHitCount(group: p.groups[2], matchedPaths: nil) == 0)
    }

    @Test("a deep-linked field resolves to the tab that contains it")
    func tabIndexForDeepLink() {
        let p = page(groupCount: 3)
        #expect(SettingsPageView.tabIndex(containing: p.groups[2].fields[0].path, page: p) == 2)
        #expect(SettingsPageView.tabIndex(containing: p.groups[0].fields[0].path, page: p) == 0)
        #expect(SettingsPageView.tabIndex(containing: SettingsPath(["nope"]), page: p) == nil)
    }
}
