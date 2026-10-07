import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// One settings page per ENABLED app — a disabled app has no settings page,
/// same as it has no Launcher entry. If the app publishes a catalog
/// (`AinkradApp.settingsCatalog(host:)`) we use its groups; otherwise its
/// `makeSettingsView` renders inside a single `.custom` field, so old
/// plugins keep working and stay findable by app name.
///
/// Every page opens on ONE "Appearance" tab: how the app opens (Open as, Open
/// in, Overlay size), then the app's own appearance fields, then the host's
/// blur toggle — see `appearanceTab`. There is no separate Surface tab.
@MainActor
enum AppSettingsCatalog {
    /// Apps that must NOT receive the host's blur toggle. None today: an app
    /// that declares its own `blur` field (Hoard, Sage) is skipped by
    /// `appearanceTab` without being listed here.
    private static var ownsItsAppearance: Set<String> { [] }

    static func pages(environment: AppEnvironment) -> [SettingsPage] {
        environment.registry.enabledApps.enumerated().map { index, app in
            let isBuiltIn = app.source == .builtIn
            let root = SettingsPath(["app", app.id])
            let published = app.settingsCatalog()

            // Everything under `published.groups` came from third-party code
            // and is untrusted at this boundary: a plugin could (deliberately
            // or by copy-paste) declare a path like ["workspace","general"]
            // or another app's ["app", otherID] and collide with a host page
            // or another plugin in `page(at:)`, deep-link resolution,
            // highlighting, and search. Re-root every group/field path under
            // this app's own `root` before it enters the catalog, so a
            // plugin can only ever address paths inside its own page — the
            // relative structure between a group and its fields (which is
            // itself part of the plugin's declared paths) is preserved
            // because the same prefix is prepended to both.
            // The fallback group is built directly by the host, already
            // rooted under `root` — only the plugin-published branch is
            // untrusted third-party input that needs re-rooting. Namespacing
            // the fallback too would double-prefix its paths
            // (["app", id, "app", id, "settings"]).
            var groups: [SettingsGroup]
            // Host-embedded built-ins whose settings need `AppEnvironment` get
            // their page built here. The SDK's `settingsCatalog(host:)` is
            // static and sees only `HostServices`, so an app like Hoard cannot
            // declare stores-backed fields through it — and falling through to
            // the `.custom` wrap below is exactly the decay the ratchet in
            // `SettingsKitCompositionTests` rejects.
            if let builtInGroups = builtInGroups(appID: app.id, root: root, environment: environment) {
                groups = builtInGroups
            } else if let published {
                groups = published.groups.map { namespaced($0, under: root) }
            } else {
                groups = [
                    SettingsGroup(
                        path: root.appending("settings"), title: app.displayName,
                        fields: [
                            SettingsField(
                                path: root.appending("settings").appending("pane"),
                                label: "\(app.displayName) settings",
                                help: nil,
                                keywords: [app.displayName.lowercased()],
                                kind: .custom(app.makeSettingsView()))
                        ])
                ]
            }

            // The surface rows join the tab for every DECLARED page. A plugin
            // still rendering one custom view draws them itself (the kit's
            // `AinkradSurfaceSettings`), so adding them here would show them twice.
            let declared = isBuiltIn || published != nil
            let tab = appearanceTab(
                appID: app.id, appName: app.displayName, root: root,
                taking: &groups, includeSurface: declared,
                environment: environment)
            if !tab.fields.isEmpty { groups.insert(tab, at: 0) }

            return SettingsPage(
                path: root, title: app.displayName, icon: app.icon,
                group: isBuiltIn ? .builtInApps : .installedApps,
                order: index, groups: groups, appID: app.id,
                badge: published?.badge)
        }
    }

    /// Prefixes every segment of `path` with `root`'s segments. Deterministic
    /// and injective, so a group and the fields declared under it keep
    /// pointing at each other after the rewrite — and the result always
    /// starts with `["app", <this app's id>, ...]`, which cannot collide
    /// with a host page (`["workspace", ...]` / `["intelligence", ...]`) or
    /// another app's page (a different id in the second segment).
    private static func namespaced(_ path: SettingsPath, under root: SettingsPath) -> SettingsPath {
        SettingsPath(root.segments + path.segments)
    }

    private static func namespaced(_ field: SettingsField, under root: SettingsPath) -> SettingsField {
        SettingsField(
            path: namespaced(field.path, under: root),
            label: field.label,
            help: field.help,
            keywords: field.keywords,
            kind: field.kind,
            isAdvanced: field.isAdvanced,
            requiresRestart: field.requiresRestart,
            defaultDescription: field.defaultDescription,
            isModified: field.isModified,
            reset: field.reset)
    }

    /// Groups for a host-embedded built-in, or `nil` if the app isn't one.
    /// These are host-authored and already rooted, so they skip the
    /// re-rooting that untrusted plugin-published groups need.
    private static func builtInGroups(
        appID: String, root: SettingsPath, environment: AppEnvironment
    ) -> [SettingsGroup]? {
        switch appID {
        case HoardApp.id: return HoardSettingsCatalog.groups(root: root, environment: environment)
        // Sage's page is its appearance, merged into the Appearance tab.
        case SageApp.id: return [HostSettingsCatalog.sageAppearanceGroup(environment, root: root)]
        // Scry has nothing of its own to set; the Appearance tab is its page.
        case ScryApp.id: return []
        default: return nil
        }
    }

    private static func namespaced(_ group: SettingsGroup, under root: SettingsPath) -> SettingsGroup {
        SettingsGroup(
            path: namespaced(group.path, under: root),
            title: group.title,
            disclosure: group.disclosure,
            footerNote: group.footerNote,
            fields: group.fields.map { namespaced($0, under: root) })
    }

    /// The page's one Appearance tab, built from:
    ///
    /// 1. how the app opens — `BuiltInSurfaceSettings`, when `includeSurface`;
    /// 2. the app's own "Appearance" group, REMOVED from `groups` and merged in
    ///    (Hoard's transparency, blur and fonts; a plugin's theme);
    /// 3. the host's blur toggle, unless the app declared one or owns its
    ///    appearance (Sage has an in-app Appearance tab).
    ///
    /// A plugin's own "Surface" group (Raven 0.4.1 declared one) is dropped
    /// when the host supplies the same rows — the host owns them now.
    private static func appearanceTab(
        appID: String, appName: String, root: SettingsPath,
        taking groups: inout [SettingsGroup], includeSurface: Bool,
        environment: AppEnvironment
    ) -> SettingsGroup {
        let path = root.appending("appearance")
        let isTitled = { (group: SettingsGroup, title: String) in
            group.title.caseInsensitiveCompare(title) == .orderedSame
        }
        let own = groups.first { isTitled($0, "Appearance") }
        groups.removeAll { isTitled($0, "Appearance") || (includeSurface && isTitled($0, "Surface")) }

        var fields =
            includeSurface
            ? BuiltInSurfaceSettings.fields(
                in: path, appID: appID, appName: appName,
                environment: environment)
            : []
        fields += own?.fields ?? []
        let declaresBlur = fields.contains { $0.path.segments.last == "blur" }
        if !declaresBlur && !ownsItsAppearance.contains(appID) && hasTransparencySlider(fields) {
            fields.append(blurField(appID: appID, group: path, environment: environment))
        }
        return SettingsGroup(
            path: path, title: "Appearance",
            footerNote: own?.footerNote ?? "How \(appName) opens, and how it looks.",
            fields: fields)
    }

    /// Blur only shows through a translucent pane, so an app with no
    /// transparency slider gets no Blur toggle — it would do nothing.
    static func hasTransparencySlider(_ fields: [SettingsField]) -> Bool {
        fields.contains {
            guard case .slider = $0.kind else { return false }
            return $0.keywords.contains("transparency")
        }
    }

    /// The blur toggle every app but the Sage gets — the host renders
    /// the blurred backdrop behind a translucent pane. `AppAppearanceStore`
    /// defaults an app's blur to off.
    private static func blurField(
        appID: String, group: SettingsPath, environment: AppEnvironment
    ) -> SettingsField {
        let store = environment.appAppearanceStore
        return SettingsField(
            path: group.appending("blur"),
            label: "Blur",
            help: "Blur the workspace revealed behind this app when it's translucent.",
            keywords: ["blur", "transparency", "translucent", "backdrop"],
            kind: .toggle(
                Binding(
                    get: { store.blurEnabled(appID) },
                    set: { store.setBlurEnabled(appID, $0) })),
            defaultDescription: "Off",
            isModified: { store.blurEnabled(appID) != false },
            reset: { store.setBlurEnabled(appID, false) })
    }
}
