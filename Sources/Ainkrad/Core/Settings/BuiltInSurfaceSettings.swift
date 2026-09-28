import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// "Open as" and "Open in" for a host-embedded built-in.
///
/// The plugins get these two rows from `AinkradSurfaceSettings`, a kit view.
/// A built-in cannot: it publishes settings as DECLARED FIELDS through
/// `SettingsCatalog` so they are searchable, deep-linkable and resettable like
/// every other setting — and wrapping a view in a `.custom` field is exactly
/// the decay the `.custom` ratchet exists to reject.
///
/// So the two surfaces differ in construction but must not differ in wording:
/// the labels and help text here are the same sentences `AinkradSurfaceSettings`
/// shows, because a setting that reads differently depending on which app you
/// found it in is two settings as far as the reader is concerned.
@MainActor
enum BuiltInSurfaceSettings {

    /// Nil when the app declares no basic mode — the "Open in" row is then
    /// omitted rather than shown inert, matching the kit view's own rule.
    static func group(root: SettingsPath,
                      appID: String,
                      appName: String,
                      environment: AppEnvironment) -> SettingsGroup {
        let appearance = environment.appAppearanceStore
        let registered = environment.registry.allApps.first { $0.id == appID }
        let declaredPresentation = registered?.presentation ?? .pane
        let declaredMode = registered?.mode ?? .advanced
        let supportsModes = registered?.supportsModes ?? false
        let group = root.appending("surface")

        var fields: [SettingsField] = [
            SettingsField(
                path: group.appending("presentation"),
                label: "Open as",
                help: "Applies the next time \(appName) opens.",
                kind: .select(
                    options: [SettingsOption(id: PluginPresentation.pane.rawValue, title: "Pane"),
                              SettingsOption(id: PluginPresentation.overlay.rawValue, title: "Overlay")],
                    selection: Binding(
                        get: { (appearance.presentationOverride(appID) ?? declaredPresentation).rawValue },
                        set: { appearance.setPresentationOverride(appID, PluginPresentation(rawValue: $0)) })),
                reset: { appearance.setPresentationOverride(appID, nil) })
        ]

        if supportsModes {
            fields.append(
                SettingsField(
                    path: group.appending("mode"),
                    label: "Open in",
                    help: "Basic shows only what \(appName) is usually opened for. "
                        + "Applies the next time it opens; you can switch a pane at any "
                        + "time without changing this.",
                    kind: .select(
                        options: [SettingsOption(id: PluginMode.basic.rawValue, title: "Basic"),
                                  SettingsOption(id: PluginMode.advanced.rawValue, title: "Advanced")],
                        selection: Binding(
                            get: { (appearance.modeOverride(appID) ?? declaredMode).rawValue },
                            set: { appearance.setModeOverride(appID, PluginMode(rawValue: $0)) })),
                    reset: { appearance.setModeOverride(appID, nil) }))
        }

        // Shown only while the app is presented as an overlay: a size that
        // applies to a surface you are not using is a control that does nothing.
        if (appearance.presentationOverride(appID) ?? declaredPresentation) == .overlay {
            fields.append(
                SettingsField(
                    path: group.appending("overlaySize"),
                    label: "Overlay size",
                    help: "How large \(appName) is drawn when it opens as an overlay. "
                        + "Applies the next time it is summoned.",
                    kind: .select(
                        options: PluginOverlaySize.allCases.map {
                            SettingsOption(id: $0.rawValue, title: $0.title)
                        },
                        selection: Binding(
                            get: { appearance.effectiveOverlaySize(appID).rawValue },
                            set: { appearance.setOverlaySizeOverride(appID, PluginOverlaySize(rawValue: $0)) })),
                    reset: { appearance.setOverlaySizeOverride(appID, nil) }))
        }

        return SettingsGroup(
            path: group,
            title: "Surface",
            footerNote: "How the host opens \(appName), and how much of it you get.",
            fields: fields)
    }
}
