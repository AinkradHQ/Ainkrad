import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// One settings page per ENABLED app — a disabled app has no settings page,
/// same as it has no Launcher entry. If the app publishes a catalog
/// (`AinkradApp.settingsCatalog(host:)`) we use its groups; otherwise its
/// `makeSettingsView` renders inside a single `.custom` field, so old
/// plugins keep working and stay findable by app name.
///
/// The host-owned "Appearance" group (the per-app blur toggle) is appended as
/// a NORMAL group, not a block bolted below whatever the app rendered. The
/// Sage is exempt — it owns its own appearance in its in-app Appearance
/// tab.
@MainActor
enum AppSettingsCatalog {
    /// App ids that declare their own appearance controls and must NOT also
    /// receive the host's auto-appended blur group.
    private static var ownsItsAppearance: Set<String> { [SageApp.id, HoardApp.id] }

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
                    SettingsGroup(path: root.appending("settings"), title: app.displayName, fields: [
                        SettingsField(
                            path: root.appending("settings").appending("pane"),
                            label: "\(app.displayName) settings",
                            help: nil,
                            keywords: [app.displayName.lowercased()],
                            kind: .custom(app.makeSettingsView()))
                    ])
                ]
            }

            // The surface rows, for a host-embedded built-in whose page is the
            // `.custom` wrap of its own view (Sage, Scry). PREPENDED rather
            // than returned instead: making them the app's only groups drops
            // that wrap, and with it every setting the app actually has —
            // caught by `AppSettingsCatalogTests`' fallback guarantee.
            //
            // Hoard is excluded because its own catalog already includes the
            // group, in the position it chose.
            if app.source == .builtIn, app.id != HoardApp.id {
                groups.insert(
                    BuiltInSurfaceSettings.group(root: root, appID: app.id,
                                                 appName: app.displayName,
                                                 environment: environment),
                    at: 0)
            }

            // Apps that own their appearance are exempt from the host's
            // auto-appended blur group: the Sage has an in-app Appearance
            // tab, and Hoard declares blur beside its own transparency slider
            // (they are one decision — blur does nothing while opaque), so
            // appending it again would strand a duplicate control in a
            // trailing group.
            if !Self.ownsItsAppearance.contains(app.id) {
                groups.append(appearanceGroup(appID: app.id, root: root, environment: environment))
            }

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

    /// The blur toggle every app but the Sage gets — the host renders
    /// the blurred backdrop behind a translucent pane. Mirrors the semantics
    /// of the former `appAppearanceSection`: `AppAppearanceStore` defaults an
    /// app's blur to off.
    private static func appearanceGroup(
        appID: String, root: SettingsPath, environment: AppEnvironment
    ) -> SettingsGroup {
        let store = environment.appAppearanceStore
        let group = root.appending("appearance")
        return SettingsGroup(path: group, title: "Appearance", fields: [
            SettingsField(
                path: group.appending("blur"),
                label: "Blur",
                help: "Blur the workspace revealed behind this app when it's translucent.",
                keywords: ["blur", "transparency", "translucent", "backdrop"],
                kind: .toggle(Binding(
                    get: { store.blurEnabled(appID) },
                    set: { store.setBlurEnabled(appID, $0) })),
                defaultDescription: "Off",
                isModified: { store.blurEnabled(appID) != false },
                reset: { store.setBlurEnabled(appID, false) })
        ])
    }
}
