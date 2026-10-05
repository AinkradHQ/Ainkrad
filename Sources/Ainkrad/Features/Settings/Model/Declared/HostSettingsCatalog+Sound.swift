import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// Sound & Voice as DECLARED rows.
@MainActor
extension HostSettingsCatalog {
    // MARK: - Sound

    static func soundFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.generalSettingsStore
        var fields = [
            generalToggle(
                environment, group.appending("enabled"), "Sound effects",
                "Plays a short chime on HUD open/close, install, and other key actions.",
                get: { $0.soundEnabled }, set: { $0.setSoundEnabled($1) }, default: defaults.soundEnabled)
        ]
        guard store.soundEnabled else { return fields }
        fields.append(
            SettingsField(
                path: group.appending("volume"), label: "Volume",
                help: "\(Int(store.soundVolume * 100))%",
                keywords: ["volume", "loud", "quiet"],
                kind: .slider(
                    range: 0...1, step: 0.05,
                    value: Binding(
                        get: { store.soundVolume }, set: { store.setSoundVolume($0) })),
                defaultDescription: "\(Int(defaults.soundVolume * 100))%",
                isModified: { store.soundVolume != defaults.soundVolume },
                reset: { store.setSoundVolume(defaults.soundVolume) }))
        // One row per cue: "Off" or the effect it plays. Choosing one previews it.
        fields += UISound.allCases.map { event in
            let options =
                [SettingsOption(id: "off", title: "Off")]
                + UISound.allCases.map {
                    SettingsOption(id: $0.rawValue, title: $0 == event ? "Default (\($0.displayName))" : $0.displayName)
                }
            return SettingsField(
                path: group.appending("cue-\(event.rawValue)"), label: event.displayName,
                help: event.eventDescription,
                keywords: ["sound", "cue", "effect", event.displayName.lowercased()],
                kind: .select(
                    options: options,
                    selection: Binding(
                        get: { store.isEventEnabled(event) ? store.effect(for: event).rawValue : "off" },
                        set: { raw in
                            guard let effect = UISound(rawValue: raw) else {
                                store.setEventEnabled(false, for: event)
                                return
                            }
                            store.setEventEnabled(true, for: event)
                            store.setEffect(effect, for: event)
                            environment.sounds.preview(effect)
                        })),
                defaultDescription: "Default (\(event.displayName))",
                isModified: { !store.isEventEnabled(event) || store.effect(for: event) != event },
                reset: {
                    store.setEventEnabled(true, for: event)
                    store.setEffect(event, for: event)
                })
        }
        return fields
    }

    // MARK: - Voice hotkey (read-only here)

    static func hotkeyField(_ environment: AppEnvironment, path: SettingsPath) -> SettingsField {
        SettingsField(
            path: path, label: "Push-to-talk hotkey",
            help: "Change this in Settings → Keyboard.",
            keywords: ["push to talk", "ptt", "chord", "dictation shortcut"],
            kind: .shortcut(.constant(environment.shortcutStore.chord(for: .pushToTalk).displayString)))
    }

    // MARK: - Speech

    private static let speechProviders = ["onDevice", "openai", "elevenlabs", "custom"]
    static let speechPresets: [(label: String, url: String)] = [
        ("Groq", "https://api.groq.com/openai/v1"),
        ("DeepInfra", "https://api.deepinfra.com/v1/openai"),
        ("Lemonfox", "https://api.lemonfox.ai/v1"),
    ]

    private static func speechSecretID(_ provider: String) -> String? {
        switch provider {
        case "openai": OpenAITTSBackend.secretID
        case "elevenlabs": ElevenLabsTTSBackend.secretID
        case "custom": OpenAITTSBackend.customSecretID
        default: nil
        }
    }

    private static func speechLabel(_ id: String) -> String {
        // Short: four options draw as a segmented control on the control rail.
        switch id {
        case "openai": "OpenAI"
        case "elevenlabs": "ElevenLabs"
        case "custom": "Custom"
        default: "On-device"
        }
    }

    static func speechFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        let settings = drafts.speech(environment.persistence)
        let secrets = environment.secrets
        let doc = settings.document
        let provider = doc.provider
        let configured = { (id: String) -> Bool in
            guard let key = speechSecretID(id) else { return true }
            let hasKey = !(secrets.secret(for: key) ?? "").isEmpty
            return id == "custom" ? hasKey && !doc.customBaseURL.isEmpty : hasKey
        }
        var fields = [
            SettingsField(
                path: group.appending("provider"), label: "Voice provider",
                help: speechSecretID(provider) == nil
                    ? "On-device speech — no key required, works offline."
                    : (configured(provider)
                        ? "Cloud voices sound more natural but need a key. On-device is free and offline."
                        : "\(speechLabel(provider)) needs setup: "
                            + (provider == "custom" ? "a base URL and an API key, below." : "an API key, below.")),
                keywords: ["tts", "speak", "read aloud", "voice", "provider"],
                kind: .select(
                    options: speechProviders.map {
                        SettingsOption(id: $0, title: speechLabel($0))
                    },
                    selection: Binding(
                        get: { settings.document.provider },
                        set: {
                            settings.setProvider($0)
                            drafts.resetSpeechDrafts()
                        })),
                defaultDescription: speechLabel("onDevice"),
                isModified: { settings.document.provider != "onDevice" },
                reset: {
                    settings.setProvider("onDevice")
                    drafts.resetSpeechDrafts()
                })
        ]
        guard let secretID = speechSecretID(provider) else { return fields }

        func text(
            _ id: String, _ label: String, _ help: String?,
            draft: ReferenceWritableKeyPath<HostSettingsDrafts, String?>,
            saved: String, save: @escaping (String) -> Void
        ) -> SettingsField {
            SettingsField(
                path: group.appending(id), label: label, help: help,
                keywords: ["tts", "voice", label.lowercased()],
                kind: .text(
                    Binding(
                        get: { drafts[keyPath: draft] ?? saved },
                        set: {
                            drafts[keyPath: draft] = $0
                            save($0)
                        })))
        }
        if provider == "custom" {
            fields.append(
                text(
                    "base-url", "Base URL", "The provider's OpenAI-compatible endpoint.",
                    draft: \.speechBaseURL, saved: doc.customBaseURL
                ) {
                    settings.setCustomBaseURL($0.trimmingCharacters(in: .whitespacesAndNewlines))
                })
            fields.append(
                SettingsField(
                    path: group.appending("preset"), label: "Endpoint preset",
                    help: "Fills in the base URL for a known provider.",
                    keywords: ["groq", "deepinfra", "lemonfox", "endpoint"],
                    kind: .select(
                        options: [SettingsOption(id: "", title: "Custom")]
                            + speechPresets.map { SettingsOption(id: $0.url, title: $0.label) },
                        selection: Binding(
                            get: { speechPresets.first { $0.url == settings.document.customBaseURL }?.url ?? "" },
                            set: { url in
                                guard !url.isEmpty else { return }
                                settings.setCustomBaseURL(url)
                                drafts.speechBaseURL = url
                            }))))
        }
        fields.append(
            SettingsField(
                path: group.appending("key"), label: "API key", help: "Kept in your Keychain.",
                keywords: ["key", "token", "api"],
                kind: .secure(
                    Binding(
                        get: { drafts.speechAPIKey ?? secrets.secret(for: secretID) ?? "" },
                        set: {
                            drafts.speechAPIKey = $0
                            secrets.setSecret($0.isEmpty ? nil : $0, for: secretID)
                        }))))
        switch provider {
        case "openai":
            fields.append(
                text("voice", "Voice", "e.g. alloy", draft: \.speechVoice, saved: doc.openAIVoice) {
                    settings.setOpenAIVoice($0.isEmpty ? "alloy" : $0)
                })
        case "elevenlabs":
            fields.append(
                text(
                    "voice", "Voice ID", "e.g. 21m00Tcm4TlvDq8ikWAM (Rachel)", draft: \.speechVoice,
                    saved: doc.elevenLabsVoiceID
                ) {
                    settings.setElevenLabsVoiceID($0.trimmingCharacters(in: .whitespacesAndNewlines))
                })
        default:
            fields.append(
                text("model", "Model", "e.g. tts-1", draft: \.speechModel, saved: doc.customModel) {
                    settings.setCustomModel($0.trimmingCharacters(in: .whitespacesAndNewlines))
                })
            fields.append(
                text("voice", "Voice", "e.g. alloy", draft: \.speechVoice, saved: doc.customVoice) {
                    settings.setCustomVoice($0.trimmingCharacters(in: .whitespacesAndNewlines))
                })
        }
        return fields
    }
}
