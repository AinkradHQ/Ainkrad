import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import AppKit
import SwiftUI

/// The workspace pages as DECLARED rows — the same shared style as every app
/// page. Each replaces a custom view that drew its own panels.
@MainActor
extension HostSettingsCatalog {
    static let defaults = GlobalSettings()

    // MARK: - General → Home

    static func homeFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        if drafts.homePath == nil {
            if !environment.isProvisionalHome, case .ready(let home) = AinkradHome.resolve() {
                drafts.homePath = .some(home.vaultRoot)
            } else {
                drafts.homePath = .some(nil)
            }
        }
        let root = drafts.homePath ?? nil
        let display: String = {
            guard let root else { return "Not set up yet" }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return root.path.hasPrefix(home) ? "~" + root.path.dropFirst(home.count) : root.path
        }()
        return [
            SettingsField(
                path: group.appending("location"),
                label: "Ainkrad Home",
                help: "\(display) — every workspace, note and project lives here. Moving it is done "
                    + "during setup, not here.",
                keywords: ["vault", "folder", "location", "path", "home", "storage"],
                kind: .action(title: "Reveal in Finder") {
                    if let root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                })
        ]
    }

    // MARK: - You

    static func profileFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        let store = environment.userProfileStore
        if drafts.profile == nil { drafts.profile = store.all() }
        return UserProfileField.all.map { field in
            SettingsField(
                path: group.appending(field.key),
                label: field.title,
                help: field.hint,
                keywords: ["profile", "about me", field.title.lowercased()],
                kind: .text(
                    Binding(
                        get: { drafts.profile?[field.key] ?? "" },
                        set: { value in
                            drafts.profile?[field.key] = value
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty { store.remove(field.key) } else { store.set(trimmed, for: field.key) }
                        })))
        }
    }

    // MARK: - Appearance

    static func themeFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let manager = environment.themeManager
        let accentTitle =
            manager.accentColorHex.map { "#" + $0.uppercased().trimmingCharacters(in: ["#"]) }
            ?? "Theme default"
        let themes = manager.themes
        let issues = manager.catalogIssues
        var fields = [
            SettingsField(
                path: group.appending("picker"), label: "Theme",
                help: "The design language — shapes, type and the whole workspace, sky included.",
                keywords: ["theme", "design", "language", "look", "neon"],
                kind: .select(
                    options: themes.map { SettingsOption(id: $0.id, title: $0.name) },
                    selection: Binding(get: { manager.activeThemeID }, set: { manager.setTheme($0) })),
                defaultDescription: themes.first { $0.id == defaults.theme }?.name ?? defaults.theme,
                isModified: { manager.currentThemeID != defaults.theme },
                reset: { manager.setTheme(defaults.theme) }),
            colorSchemeField(manager, .dark, group: group),
        ]
        // Only a theme with a light variant has a light scheme to pick.
        if manager.defaultColorSchemeID(for: .light) != nil {
            fields.append(colorSchemeField(manager, .light, group: group))
        }
        let filesField = SettingsField(
            path: group.appending("files"), label: "Theme files",
            help: "Themes and colour schemes are loaded from the app and from your Home's Config/Themes folder.",
            keywords: ["theme", "colour", "color scheme", "files", "errors"],
            kind: .action(
                title: issues.isEmpty
                    ? "All loaded" : "\(issues.count) file\(issues.count == 1 ? "" : "s") could not load"
            ) { environment.settingsDrafts.showsThemeFiles = true })
        return fields + [
            SettingsField(
                path: group.appending("accent"), label: "Accent",
                help: "Used for anything live: selection, focus, the things that are currently doing something.",
                keywords: ["accent", "color", "highlight"],
                kind: .action(title: accentTitle) {
                    SettingsColorPanel.shared.edit(manager.hostSkin.color(\.accentPrimary)) { manager.setAccentColor($0) }
                },
                defaultDescription: "the theme's accent",
                isModified: { manager.accentColorHex != nil },
                reset: { manager.setAccentColorHex(nil) }),
            SettingsField(
                path: group.appending("font-size"), label: "Text size",
                help: "Every word in the app, including the ones you are reading now.",
                keywords: ["font", "size", "scale", "text"],
                kind: .select(
                    options: UIFontScale.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                    selection: Binding(
                        get: { manager.uiFontScale.rawValue },
                        set: { if let s = UIFontScale(rawValue: $0) { manager.setFontScale(s) } })),
                defaultDescription: defaults.uiFontScale.title,
                isModified: { manager.uiFontScale != defaults.uiFontScale },
                reset: { manager.setFontScale(defaults.uiFontScale) }),
            SettingsField(
                path: group.appending("typeface"), label: "Typeface",
                keywords: ["font", "typeface", "family"],
                kind: .select(
                    options: UIFontFamily.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                    selection: Binding(
                        get: { manager.uiFontFamily.rawValue },
                        set: { if let f = UIFontFamily(rawValue: $0) { manager.setFontFamily(f) } })),
                defaultDescription: defaults.uiFontFamily.title,
                isModified: { manager.uiFontFamily != defaults.uiFontFamily },
                reset: { manager.setFontFamily(defaults.uiFontFamily) }),
            generalToggle(
                environment, group.appending("reduce-motion"), "Reduce motion",
                "Turns off transitions, parallax, blinking cursors, and other animation across "
                    + "Ainkrad. Independent of the macOS Reduce Motion setting.",
                get: { $0.uiReduceMotion }, set: { $0.setUiReduceMotion($1) },
                default: defaults.uiReduceMotion),
            filesField,
        ]
    }

    /// One colour-scheme select per appearance; nil (the reset) follows the theme.
    private static func colorSchemeField(
        _ manager: ThemeManager, _ appearance: ThemeAppearance, group: SettingsPath
    ) -> SettingsField {
        let schemes = manager.colorSchemes(for: appearance)
        let fallback = manager.defaultColorSchemeID(for: appearance) ?? ""
        let defaultName = schemes.first { $0.id == fallback }?.name ?? fallback
        return SettingsField(
            path: group.appending("scheme-\(appearance.rawValue)"),
            label: appearance == .dark ? "Dark colour scheme" : "Light colour scheme",
            help: "The colours on top of the theme: palette, terminal and the sky's tint.",
            keywords: ["theme", "colour", "color", "color scheme", "palette", "light", "dark", "dark mode"],
            kind: .select(
                options: schemes.map { SettingsOption(id: $0.id, title: $0.name) },
                selection: Binding(
                    get: {
                        manager.colorSchemeID(for: appearance).flatMap { id in
                            schemes.contains { $0.id == id } ? id : nil
                        } ?? fallback
                    },
                    set: { manager.setColorScheme($0, for: appearance) })),
            defaultDescription: "Theme default (\(defaultName))",
            isModified: { manager.colorSchemeID(for: appearance) != nil },
            reset: { manager.setColorScheme(nil, for: appearance) })
    }

    static func overlayFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.generalSettingsStore
        return [
            SettingsField(
                path: group.appending("opacity"), label: "Overlay opacity",
                help: "\(Int(store.overlayBackgroundOpacity * 100))%. Lower lets the workspace show through "
                    + "the Launcher, Settings, App Store, notifications and every other overlay.",
                keywords: ["overlay", "opacity", "transparency", "glass"],
                kind: .slider(
                    range: 0.3...1.0, step: 0.02,
                    value: Binding(
                        get: { store.overlayBackgroundOpacity }, set: { store.setOverlayBackgroundOpacity($0) })),
                defaultDescription: "\(Int(defaults.overlayBackgroundOpacity * 100))%",
                isModified: { store.overlayBackgroundOpacity != defaults.overlayBackgroundOpacity },
                reset: { store.setOverlayBackgroundOpacity(defaults.overlayBackgroundOpacity) }),
            generalToggle(
                environment, group.appending("blur"), "Overlay blur",
                "Blur the workspace behind overlays.",
                get: { $0.overlayBlurEnabled }, set: { $0.setOverlayBlurEnabled($1) },
                default: defaults.overlayBlurEnabled),
        ]
    }

    static func livingSkyFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let sky = environment.skySettingsStore
        var fields = [
            SettingsField(
                path: group.appending("motion"), label: "Animate the sky",
                help: "Freezes every ambient effect in place when off — the scene stays, the motion stops.",
                keywords: ["animation", "motion", "sky", "background"],
                kind: .toggle(Binding(get: { sky.motionEnabled }, set: { sky.setMotionEnabled($0) })),
                defaultDescription: "On",
                isModified: { sky.motionEnabled != defaults.skyMotionEnabled },
                reset: { sky.setMotionEnabled(defaults.skyMotionEnabled) })
        ]
        if sky.motionEnabled {
            fields.append(
                SettingsField(
                    path: group.appending("speed"), label: "Motion speed",
                    keywords: ["speed", "animation", "slow", "fast"],
                    kind: .select(
                        options: SkySettingsStore.speedPresets.map {
                            SettingsOption(id: "\($0.value)", title: $0.title)
                        },
                        selection: Binding(
                            get: { "\(SkySettingsStore.nearestPreset(to: sky.motionSpeed))" },
                            set: { if let v = Double($0) { sky.setMotionSpeed(v) } })),
                    defaultDescription: SkySettingsStore.presetTitle(defaults.skyMotionSpeed),
                    isModified: { SkySettingsStore.nearestPreset(to: sky.motionSpeed) != defaults.skyMotionSpeed },
                    reset: { sky.setMotionSpeed(defaults.skyMotionSpeed) }))
        }
        fields += SkyEffect.allCases.map { effect in
            SettingsField(
                path: group.appending("effect-\(effect.rawValue)"), label: effect.displayName,
                help: effect.effectDescription,
                keywords: ["sky", "effect", effect.displayName.lowercased()],
                kind: .toggle(Binding(get: { sky.isEnabled(effect) }, set: { sky.setEnabled($0, for: effect) })),
                defaultDescription: "On",
                isModified: { !sky.isEnabled(effect) },
                reset: { sky.setEnabled(true, for: effect) })
        }
        return fields
    }

    static func appIconFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.appIconStore
        return [
            SettingsField(
                path: group.appending("color"), label: "Icon color",
                help: "The icon Ainkrad shows in the Dock. Auto follows your theme.",
                keywords: ["dock", "icon", "color"],
                kind: .select(
                    options: AppIconChoice.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                    selection: Binding(
                        get: { store.choice.rawValue },
                        set: { if let c = AppIconChoice(rawValue: $0) { store.selectColor(c) } })),
                defaultDescription: defaults.appIconChoice.title,
                isModified: { store.choice != defaults.appIconChoice },
                reset: { store.selectColor(defaults.appIconChoice) }),
            SettingsField(
                path: group.appending("appearance"), label: "Icon appearance",
                help: "System follows the Dock's light or dark.",
                keywords: ["dock", "icon", "light", "dark"],
                kind: .select(
                    options: AppIconAppearance.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                    selection: Binding(
                        get: { store.appearance.rawValue },
                        set: { if let a = AppIconAppearance(rawValue: $0) { store.selectAppearance(a) } })),
                defaultDescription: defaults.appIconAppearance.title,
                isModified: { store.appearance != defaults.appIconAppearance },
                reset: { store.selectAppearance(defaults.appIconAppearance) }),
        ]
    }

    /// A toggle backed by `GeneralSettingsStore`, with its default and reset.
    static func generalToggle(
        _ environment: AppEnvironment, _ path: SettingsPath, _ label: String,
        _ help: String?,
        get: @escaping (GeneralSettingsStore) -> Bool,
        set: @escaping (GeneralSettingsStore, Bool) -> Void,
        default fallback: Bool
    ) -> SettingsField {
        let store = environment.generalSettingsStore
        return SettingsField(
            path: path, label: label, help: help, keywords: [label.lowercased()],
            kind: .toggle(Binding(get: { get(store) }, set: { set(store, $0) })),
            defaultDescription: fallback ? "On" : "Off",
            isModified: { get(store) != fallback },
            reset: { set(store, fallback) })
    }
}

extension UIFontScale {
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

extension UIFontFamily {
    var title: String {
        switch self {
        case .exo2: "Exo 2"
        case .jetBrainsMono: "JetBrains Mono"
        case .system: "System"
        }
    }
}

extension AppIconChoice {
    var title: String {
        switch self {
        case .auto: "Auto"
        case .blue: "Blue"
        case .purple: "Purple"
        }
    }
}

extension AppIconAppearance {
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
