import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Assembles the host's own settings pages into descriptors. Each field
/// binds straight through to the existing store — the catalog describes
/// settings, it does not own their persistence.
///
/// This builds the WORKSPACE pages (General, Appearance, Sound & Voice,
/// Keyboard), appends the INTELLIGENCE pages from
/// `IntelligenceSettingsCatalog`, and the APPS pages (BUILT-IN APPS /
/// INSTALLED) from `AppSettingsCatalog`.
@MainActor
enum HostSettingsCatalog {
    static func build(environment: AppEnvironment) -> SettingsCatalog {
        SettingsCatalog(pages: [
            general(environment),
            you(environment),
            appearance(environment),
            soundAndVoice(environment),
            keyboard(environment)
        ] + notificationsPages(environment) + IntelligenceSettingsCatalog.pages(environment: environment)
          + AppSettingsCatalog.pages(environment: environment))
    }

    // MARK: - Notifications

    /// Wraps the hand-rolled `SignalSettingsPane` in a catalog page, so it is
    /// searchable and deep-linkable like every other setting.
    ///
    /// **This pane existed and was unreachable.** It was built in M1, rendered
    /// in a snapshot for review, and never placed in the navigation — so every
    /// delivery rule, the retention limits and "Clear feed" were live code with
    /// no way in. Found while adding the cross-app access section, whose
    /// Revoke control would have been just as unreachable.
    ///
    /// Returns an empty array when the center does not exist (the feed degraded
    /// to nothing at launch): a settings page that cannot show the truth about
    /// the subsystem it configures is worse than an absent one.
    private static func notificationsPages(_ environment: AppEnvironment) -> [SettingsPage] {
        guard let center = environment.signalCenter else { return [] }
        let page = SettingsPath(["workspace", "notifications"])
        return [SettingsPage(
            path: page, title: "Notifications", icon: "bell",
            group: .workspace, order: 5,
            groups: [
                SettingsGroup(path: page.appending("feed"), title: "Notifications", fields: [
                    SettingsField(
                        path: page.appending("feed").appending("pane"),
                        label: "Notifications",
                        help: "What each source may interrupt you with, how long the feed "
                            + "keeps events, and which apps may read other apps' notifications.",
                        keywords: ["notification", "signal", "feed", "toast", "banner",
                                   "badge", "mute", "retention", "subscription", "permission"],
                        kind: .custom(AnyView(NotificationsSettingsView(center: center))))
                ])
            ])]
    }

    // MARK: - General

    private static func general(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "general"])
        let startup = page.appending("startup")
        let store = environment.generalSettingsStore

        return SettingsPage(
            path: page, title: "General", icon: "gearshape",
            group: .workspace, order: 0,
            groups: [
                SettingsGroup(path: startup, title: "Workspace", fields: [
                    SettingsField(
                        path: startup.appending("fullScreenStatusBar"),
                        label: "Show status bar in full-screen",
                        help: "Clock, network, and battery in the title strip while full-screen.",
                        keywords: ["clock", "battery", "network", "menu bar"],
                        kind: .toggle(Binding(
                            get: { store.showFullScreenStatusBar },
                            set: { store.setShowFullScreenStatusBar($0) })),
                        defaultDescription: "On",
                        isModified: { store.showFullScreenStatusBar != true },
                        reset: { store.setShowFullScreenStatusBar(true) }),
                    SettingsField(
                        path: startup.appending("launcherLayout"),
                        label: "Launcher layout",
                        help: "Show apps in the ⌘K launcher as a list or a grid of icons.",
                        keywords: ["grid", "list", "command k", "apps"],
                        kind: .select(
                            options: LauncherViewMode.allCases.map {
                                SettingsOption(id: $0.rawValue, title: $0.label)
                            },
                            selection: Binding(
                                get: { store.launcherViewMode.rawValue },
                                set: { raw in
                                    guard let mode = LauncherViewMode(rawValue: raw) else { return }
                                    store.setLauncherViewMode(mode)
                                })),
                        defaultDescription: LauncherViewMode.allCases[0].label,
                        isModified: { store.launcherViewMode != LauncherViewMode.allCases[0] },
                        reset: { store.setLauncherViewMode(LauncherViewMode.allCases[0]) })
                ]),
                SettingsGroup(path: page.appending("home"), title: "Home", fields: [
                    SettingsField(
                        path: page.appending("home").appending("location"),
                        label: "Ainkrad Home",
                        help: "The folder holding all of your workspaces and notes.",
                        keywords: ["vault", "folder", "location", "path", "home", "storage"],
                        kind: .custom(AnyView(HomeSettingsView()))),
                    SettingsField(
                        path: page.appending("home").appending("rerunSetup"),
                        label: "Re-run setup",
                        help: "Walk through the first-run wizard again. Your Home folder is "
                            + "not re-asked, and nothing is reset until you change it.",
                        keywords: ["wizard", "setup", "first run", "onboarding", "welcome"],
                        kind: .action(title: "Re-run setup") {
                            environment.isSettingsPresented = false
                            environment.isSetupReplay = true
                            environment.isSetupPresented = true
                        })
                ])
            ])
    }

    // MARK: - You

    /// The wizard's You step, made editable after first run.
    private static func you(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "you"])
        return SettingsPage(
            path: page, title: "You", icon: "person",
            group: .workspace, order: 1,
            groups: [
                SettingsGroup(path: page.appending("profile"), title: "Profile", fields: [
                    SettingsField(
                        path: page.appending("profile").appending("fields"),
                        label: "About you",
                        help: "Your name, role and timezone, as the assistant knows them.",
                        keywords: ["name", "profile", "role", "timezone", "about me", "user"],
                        kind: .custom(AnyView(UserProfileSettingsView())))
                ])
            ])
    }

    // MARK: - Appearance (theme + Living Sky + App Icon merged)

    private static func appearance(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "appearance"])
        return SettingsPage(
            path: page, title: "Appearance", icon: "paintbrush",
            group: .workspace, order: 2,
            groups: [
                SettingsGroup(path: page.appending("theme"), title: "Theme", fields: [
                    SettingsField(
                        path: page.appending("theme").appending("picker"),
                        label: "Theme",
                        help: "Accent palette for the whole workspace.",
                        keywords: ["accent", "color", "dark mode", "neon", "palette"],
                        kind: .custom(AnyView(AppearanceSettingsView())))
                ]),
                SettingsGroup(path: page.appending("livingSky"), title: "Living Sky", fields: [
                    SettingsField(
                        path: page.appending("livingSky").appending("controls"),
                        label: "Living Sky",
                        help: "The animated backdrop behind the workspace.",
                        keywords: ["background", "wallpaper", "animation", "parallax"],
                        kind: .custom(AnyView(LivingSkySettingsView())))
                ]),
                // Always expanded. This page is tabbed (3 groups), so the icon
                // picker already sits behind one hiding mechanism; collapsing
                // it too is what produced "I can't find the app icons
                // settings". `AppIconSettingsView` renders its own
                // `AinkradSettingsPanel(title: "App icon", ...)`, so the tab
                // label plus that panel's title label it fine without the
                // catalog's disclosure header.
                SettingsGroup(path: page.appending("appIcon"), title: "App Icon", fields: [
                    SettingsField(
                        path: page.appending("appIcon").appending("picker"),
                        label: "App icon",
                        help: "The icon Ainkrad shows in the Dock.",
                        keywords: ["dock", "icon", "badge"],
                        kind: .custom(AnyView(AppIconSettingsView())))
                ])
            ])
    }

    // MARK: - Sound & Voice

    private static func soundAndVoice(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "soundAndVoice"])
        let tokens = environment.themeManager.tokens
        return SettingsPage(
            path: page, title: "Sound & Voice", icon: "speaker.wave.2",
            group: .workspace, order: 3,
            groups: [
                // Sound stays a `.custom` pane DELIBERATELY. It was decomposed
                // in Task 7 and reverted after review: each of the 13 `UISound`
                // events needs an enable toggle, an effect chooser AND a
                // preview action, which one-field-per-control turns into three
                // rows with near-duplicate labels ("Startup" / "Startup sound"
                // / "Preview Startup") thirteen times over — worse than the
                // pane. A correct conversion needs a COMPOSITE row kind the SDK
                // does not have yet; until then this is the right use of the
                // escape hatch. Voice, directly below, decomposed cleanly.
                SettingsGroup(path: page.appending("sound"), title: "Sound", fields: [
                    SettingsField(
                        path: page.appending("sound").appending("effects"),
                        label: "Sound effects",
                        help: "Workspace interaction sounds.",
                        keywords: ["audio", "volume", "mute", "chime"],
                        kind: .custom(AnyView(SoundSettingsView())))
                ]),
                voiceGroup(environment, page: page),
                SettingsGroup(path: page.appending("speech"), title: "Speech", fields: [
                    SettingsField(
                        path: page.appending("speech").appending("textToSpeech"),
                        label: "Spoken responses",
                        help: "How the assistant reads its replies aloud.",
                        keywords: ["tts", "speak", "read aloud", "voice"],
                        kind: .custom(AnyView(TTSSettingsView(
                            persistence: environment.persistence,
                            secrets: environment.secrets,
                            tokens: tokens))))
                ])
            ])
    }

    private static func voiceGroup(_ environment: AppEnvironment, page: SettingsPath) -> SettingsGroup {
        let voice = page.appending("voice")
        // The voice store lives on the service — there is no
        // `environment.voiceSettingsStore`.
        let settings = environment.voiceService.settings
        let connections = environment.connectionStore
        let shortcuts = environment.shortcutStore
        let tokens = environment.themeManager.tokens

        func backendTitle(_ kind: TranscriptionBackendKind) -> String {
            kind == .onDevice ? "On-device (private)" : "Provider (Whisper)"
        }

        return SettingsGroup(path: voice, title: "Voice", fields: [
            SettingsField(
                path: voice.appending("backend"),
                label: "Backend",
                help: "On-device keeps audio private; Provider sends it to a configured connection.",
                keywords: ["transcription", "whisper", "on-device", "offline", "stt", "engine"],
                kind: .select(
                    options: TranscriptionBackendKind.allCases.map {
                        SettingsOption(id: $0.rawValue, title: backendTitle($0))
                    },
                    selection: Binding(
                        get: { settings.document.backend.rawValue },
                        set: { raw in
                            guard let kind = TranscriptionBackendKind(rawValue: raw) else { return }
                            settings.setBackend(kind)
                        })),
                defaultDescription: backendTitle(.onDevice),
                isModified: { settings.document.backend != .onDevice },
                reset: { settings.setBackend(.onDevice) }),
            SettingsField(
                path: voice.appending("mode"),
                label: "Push-to-talk mode",
                help: "Hold records while the hotkey is down; Toggle starts and stops on separate presses.",
                keywords: ["hold", "toggle", "ptt", "dictation", "microphone"],
                kind: .select(
                    options: PushToTalkMode.allCases.map {
                        SettingsOption(id: $0.rawValue, title: $0 == .hold ? "Hold" : "Toggle")
                    },
                    selection: Binding(
                        get: { settings.document.mode.rawValue },
                        set: { raw in
                            guard let mode = PushToTalkMode(rawValue: raw) else { return }
                            settings.setMode(mode)
                        })),
                defaultDescription: "Hold",
                isModified: { settings.document.mode != .hold },
                reset: { settings.setMode(.hold) }),
            SettingsField(
                path: voice.appending("autoSend"),
                label: "Auto-send after dictation",
                help: "Sends the transcript to the assistant as soon as dictation ends.",
                keywords: ["send", "submit", "dictation", "automatic", "enter"],
                kind: .toggle(Binding(
                    get: { settings.document.autoSend },
                    set: { settings.setAutoSend($0) })),
                // Reads as an affirmative label but the store default is false.
                defaultDescription: "Off",
                isModified: { settings.document.autoSend != false },
                reset: { settings.setAutoSend(false) }),
            SettingsField(
                path: voice.appending("providerOptIn"),
                label: "Upload audio to provider",
                help: "Opt in to sending dictated audio to the selected connection for transcription.",
                keywords: ["upload", "opt-in", "privacy", "cloud", "consent"],
                kind: .toggle(Binding(
                    get: { settings.document.providerOptIn },
                    set: { settings.setProviderOptIn($0) })),
                defaultDescription: "Off",
                isModified: { settings.document.providerOptIn != false },
                reset: { settings.setProviderOptIn(false) }),
            SettingsField(
                path: voice.appending("connection"),
                label: "Connection",
                help: "Which configured connection transcribes uploaded audio.",
                keywords: ["provider", "endpoint", "openai", "server", "account"],
                kind: .select(
                    options: connections.connections.map {
                        SettingsOption(id: $0.id.uuidString, title: $0.displayName)
                    },
                    selection: Binding(
                        get: { settings.document.providerConnectionID?.uuidString
                            ?? connections.connections.first?.id.uuidString ?? "" },
                        set: { settings.setProviderConnection(UUID(uuidString: $0)) })),
                defaultDescription: "None",
                isModified: { settings.document.providerConnectionID != nil },
                reset: { settings.setProviderConnection(nil) }),
            // Not `.secure`: this is a MODEL NAME ("whisper-1"), not a
            // credential. Marking it secure would hide it from search for no
            // security gain. The TTS API key is the page's only real secret and
            // it lives in the out-of-scope `TTSSettingsView` pane.
            SettingsField(
                path: voice.appending("providerModel"),
                label: "Model",
                help: "Transcription model requested from the provider.",
                keywords: ["whisper", "model", "engine", "name"],
                kind: .text(Binding(
                    get: { settings.document.providerModel },
                    set: { settings.setProviderModel($0) })),
                defaultDescription: "whisper-1",
                isModified: { settings.document.providerModel != "whisper-1" },
                reset: { settings.setProviderModel("whisper-1") }),
            SettingsField(
                path: voice.appending("locale"),
                label: "Locale",
                help: "Language hint for speech recognition, as a BCP-47 tag.",
                keywords: ["language", "region", "bcp-47", "en-US", "accent"],
                kind: .text(Binding(
                    get: { settings.document.localeIdentifier },
                    set: { settings.setLocale($0) })),
                defaultDescription: "en-US",
                isModified: { settings.document.localeIdentifier != "en-US" },
                reset: { settings.setLocale("en-US") }),
            // The one deliberate `.custom` here: a READ-ONLY display of the
            // current chord. It is rebound in Settings → Keyboard, so there is
            // nothing to edit; the kit has no informational field kind and one
            // is not worth adding for a single row.
            SettingsField(
                path: voice.appending("hotkey"),
                label: "Push-to-talk hotkey",
                help: "Change this in Settings → Keyboard.",
                // Deliberately NOT "hotkey": Keyboard ▸ "Keyboard shortcuts" is
                // where a chord is actually rebound and must stay the top hit
                // for that word. This row is a read-only pointer to it.
                keywords: ["push to talk", "ptt", "chord", "dictation shortcut"],
                kind: .custom(AnyView(VoiceHotkeyDisplay(shortcuts: shortcuts, tokens: tokens))))
        ])
    }

    // MARK: - Keyboard

    private static func keyboard(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "keyboard"])
        return SettingsPage(
            path: page, title: "Keyboard", icon: "keyboard",
            group: .workspace, order: 4,
            groups: [
                SettingsGroup(path: page.appending("shortcuts"), title: "Shortcuts", fields: [
                    SettingsField(
                        path: page.appending("shortcuts").appending("list"),
                        label: "Keyboard shortcuts",
                        help: "Global and workspace key bindings.",
                        keywords: ["hotkey", "binding", "key", "chord", "command"],
                        kind: .custom(AnyView(ShortcutsSettingsView())))
                ])
            ])
    }
}
