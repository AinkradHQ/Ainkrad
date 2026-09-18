import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Hoard' settings as DECLARED fields.
///
/// Built here rather than in `HoardApp.settingsCatalog(host:)` because that
/// entry point is static and sees only `HostServices` — it cannot reach
/// `AppEnvironment`, where the appearance and Hoard stores live. Since Hoard is
/// a host-embedded built-in (not a loadable plugin), the host is entitled to
/// build its page directly; see `AppSettingsCatalog`'s built-in seam.
///
/// Declared fields rather than one `.custom` wrapped view, so these settings
/// are searchable, deep-linkable and resettable like every other setting — and
/// so they don't trip the `.custom` ratchet.
///
/// **Organisation:** two groups, ordered by how often they're reached for.
/// *Appearance* holds everything about how the pane looks as a surface —
/// transparency and blur adjacent because they're the same decision (blur only
/// does anything when translucent), then the font overrides. *List* holds what
/// changes the file list itself. Hoard is exempted from the host's
/// auto-appended blur group precisely so blur can live beside transparency
/// instead of stranded in a fourth group below the fonts.
@MainActor
enum HoardSettingsCatalog {
    static func groups(root: SettingsPath, environment: AppEnvironment) -> [SettingsGroup] {
        // Surface first: whether Hoard opens basic or advanced decides what you
        // GET when you open it, which outranks how it looks.
        [BuiltInSurfaceSettings.group(root: root, appID: HoardApp.id,
                                      appName: HoardApp.displayName, environment: environment),
         appearanceGroup(root: root, environment: environment),
         listGroup(root: root, environment: environment)]
    }

    private static func appearanceGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let appearance = environment.appAppearanceStore
        let manager = environment.themeManager
        let group = root.appending("appearance")

        let familyOptions = [SettingsOption(id: "default", title: "Default (follow Appearance)")]
            + UIFontFamily.allCases.map { SettingsOption(id: $0.rawValue, title: familyTitle($0)) }
        let scaleOptions = [SettingsOption(id: "default", title: "Default (follow Appearance)")]
            + UIFontScale.allCases.map { SettingsOption(id: $0.rawValue, title: scaleTitle($0)) }

        return SettingsGroup(
            path: group,
            title: "Appearance",
            footerNote: "Blur only has an effect while the pane is translucent — the host draws the workspace island behind it.",
            fields: [
                SettingsField(
                    path: group.appending("opacity"),
                    label: "Transparency",
                    help: "Lower values reveal the workspace island behind the pane. The title bar follows the same value, so the window stays one continuous surface.",
                    keywords: ["transparency", "opacity", "translucent", "island", "glass"],
                    kind: .slider(range: 0.3...1.0, step: 0.05, value: Binding(
                        get: { appearance.surfaceOpacity(HoardApp.id) },
                        set: { appearance.setSurfaceOpacity(HoardApp.id, $0) })),
                    defaultDescription: "Opaque",
                    isModified: { appearance.surfaceOpacity(HoardApp.id) != 1.0 },
                    reset: { appearance.setSurfaceOpacity(HoardApp.id, 1.0) }),
                SettingsField(
                    path: group.appending("blur"),
                    label: "Blur",
                    help: "Blur the workspace revealed behind this app when it's translucent.",
                    keywords: ["blur", "transparency", "translucent", "backdrop"],
                    kind: .toggle(Binding(
                        get: { appearance.blurEnabled(HoardApp.id) },
                        set: { appearance.setBlurEnabled(HoardApp.id, $0) })),
                    defaultDescription: "Off",
                    isModified: { appearance.blurEnabled(HoardApp.id) != false },
                    reset: { appearance.setBlurEnabled(HoardApp.id, false) }),
                SettingsField(
                    path: group.appending("font-family"),
                    label: "Font",
                    help: "Override the workspace font for this app only.",
                    keywords: ["font", "typeface", "family", "typography"],
                    kind: .select(options: familyOptions, selection: Binding(
                        get: { appearance.fontFamily(HoardApp.id)?.rawValue ?? "default" },
                        set: { appearance.setFontFamily(HoardApp.id, UIFontFamily(rawValue: $0)) })),
                    defaultDescription: familyTitle(manager.uiFontFamily),
                    isModified: { appearance.fontFamily(HoardApp.id) != nil },
                    reset: { appearance.setFontFamily(HoardApp.id, nil) }),
                SettingsField(
                    path: group.appending("font-scale"),
                    label: "Font size",
                    help: "Override the workspace font scale for this app only.",
                    keywords: ["font size", "scale", "text size", "typography"],
                    kind: .select(options: scaleOptions, selection: Binding(
                        get: { appearance.fontScale(HoardApp.id)?.rawValue ?? "default" },
                        set: { appearance.setFontScale(HoardApp.id, UIFontScale(rawValue: $0)) })),
                    defaultDescription: scaleTitle(manager.uiFontScale),
                    isModified: { appearance.fontScale(HoardApp.id) != nil },
                    reset: { appearance.setFontScale(HoardApp.id, nil) })
            ])
    }

    private static func listGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let store = environment.filesSettingsStore
        let group = root.appending("list")
        return SettingsGroup(
            path: group,
            title: "List",
            footerNote: "Row height follows the icon size, so it doubles as the list's density control.",
            fields: [
                SettingsField(
                    path: group.appending("icon-size"),
                    label: "Icon size",
                    help: "Row icon size, in points.",
                    keywords: ["icon", "size", "density", "row height", "compact"],
                    kind: .slider(range: 10...22, step: 1, value: Binding(
                        get: { store.iconSize },
                        set: { store.iconSize = $0 })),
                    defaultDescription: "13 pt",
                    isModified: { store.iconSize != 13 },
                    reset: { store.iconSize = 13 }),
                SettingsField(
                    path: group.appending("preview"),
                    label: "Preview pane",
                    help: "Show a preview strip beside the list. ⌘Y toggles it. (⌥F focuses the in-pane search; ⌘F searches everywhere.)",
                    keywords: ["preview", "quick look", "sidebar", "inspector"],
                    kind: .toggle(Binding(
                        get: { store.showPreview },
                        set: { store.showPreview = $0 })),
                    defaultDescription: "Off",
                    isModified: { store.showPreview != false },
                    reset: { store.showPreview = false }),
                SettingsField(
                    path: group.appending("grid"),
                    label: "Grid view",
                    help: "Show files as an icon grid instead of a list. Cell size follows the icon size.",
                    keywords: ["grid", "icons", "thumbnails", "gallery", "view mode"],
                    kind: .toggle(Binding(
                        get: { store.useGrid },
                        set: { store.useGrid = $0 })),
                    defaultDescription: "Off",
                    isModified: { store.useGrid != false },
                    reset: { store.useGrid = false }),
                SettingsField(
                    path: group.appending("vim-keys"),
                    label: "Vim navigation (hjkl)",
                    help: "Bind h/j/k/l and g/G for navigation. Off by default because it conflicts with type-to-select.",
                    keywords: ["vim", "hjkl", "modal", "keyboard", "navigation"],
                    kind: .toggle(Binding(
                        get: { store.vimKeys },
                        set: { store.vimKeys = $0 })),
                    defaultDescription: "Off",
                    isModified: { store.vimKeys != false },
                    reset: { store.vimKeys = false }),
                SettingsField(
                    path: group.appending("metadata-columns"),
                    label: "Show size and date",
                    help: "Turn off for a name-only list.",
                    keywords: ["columns", "size", "date", "modified", "metadata"],
                    kind: .toggle(Binding(
                        get: { store.showMetadataColumns },
                        set: { store.showMetadataColumns = $0 })),
                    defaultDescription: "On",
                    isModified: { store.showMetadataColumns != true },
                    reset: { store.showMetadataColumns = true })
            ])
    }

    private static func familyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    private static func scaleTitle(_ scale: UIFontScale) -> String {
        switch scale {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}
