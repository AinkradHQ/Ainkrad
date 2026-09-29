import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Tools → Web search, Images and Video as DECLARED rows. All three are the
/// same shape: pick a provider, then the rows that provider needs (key, model,
/// URL). Keys live only in the Keychain.
@MainActor
extension HostSettingsCatalog {
    struct ProviderChoice {
        let id: String
        let label: String
        let secretID: String?
    }

    // MARK: - Shared rows

    /// A text row that keeps what is typed and saves it (trimmed) as it goes.
    static func draftText(_ environment: AppEnvironment, _ path: SettingsPath, _ label: String,
                          _ help: String?, saved: String, save: @escaping (String) -> Void) -> SettingsField {
        let drafts = environment.settingsDrafts
        let key = path.segments.joined(separator: ".")
        return SettingsField(path: path, label: label, help: help, keywords: [label.lowercased()],
                             kind: .text(Binding(get: { drafts.text[key] ?? saved },
                                                 set: { drafts.text[key] = $0
                                                        save($0.trimmingCharacters(in: .whitespacesAndNewlines)) })))
    }

    static func keyRow(_ environment: AppEnvironment, _ path: SettingsPath, secretID: String) -> SettingsField {
        let drafts = environment.settingsDrafts
        let secrets = environment.secrets
        return SettingsField(
            path: path, label: "API key", help: "Kept in your Keychain only.",
            keywords: ["key", "token", "api"],
            kind: .secure(Binding(get: { drafts.text[secretID] ?? secrets.secret(for: secretID) ?? "" },
                                  set: { drafts.text[secretID] = $0; secrets.setSecret($0.isEmpty ? nil : $0, for: secretID) })))
    }

    static func providerRow(_ path: SettingsPath, label: String, help: String, choices: [ProviderChoice],
                            current: @escaping () -> String, set: @escaping (String) -> Void,
                            fallback: String) -> SettingsField {
        SettingsField(
            path: path, label: label, help: help, keywords: ["provider", label.lowercased()],
            kind: .select(options: choices.map { SettingsOption(id: $0.id, title: $0.label) },
                          selection: Binding(get: current, set: set)),
            defaultDescription: choices.first { $0.id == fallback }?.label,
            isModified: { current() != fallback },
            reset: { set(fallback) })
    }

    /// "Needs setup" help for a provider that is chosen but not usable yet.
    static func setupHelp(_ ready: Bool, _ what: String, otherwise: String) -> String {
        ready ? otherwise : "Needs setup: \(what), below."
    }

    // MARK: - Web search

    static func webSearchFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let settings = environment.webSearchSettingsStore
        let secrets = environment.secrets
        let provider = settings.document.provider
        let hasKey = !(secrets.secret(for: BraveSearchBackend.secretID) ?? "").isEmpty
        let help: String = switch provider {
        case "searxng": setupHelp(!settings.document.searxngURL.isEmpty, "an instance URL",
                                  otherwise: "No key or card. A public instance or your own, with the JSON API enabled.")
        case "duckduckgo": "No key required. Results come from DuckDuckGo's HTML, so they can occasionally be empty."
        default: setupHelp(hasKey, "an API key", otherwise: "The search provider the assistant queries.")
        }
        var fields = [providerRow(
            group.appending("provider"), label: "Search provider", help: help,
            choices: [.init(id: "brave", label: "Brave Search", secretID: BraveSearchBackend.secretID),
                      .init(id: "searxng", label: "SearXNG", secretID: nil),
                      .init(id: "duckduckgo", label: "DuckDuckGo", secretID: nil)],
            current: { settings.document.provider }, set: { settings.setProvider($0) },
            fallback: "brave")]
        switch provider {
        case "brave": fields.append(keyRow(environment, group.appending("key"), secretID: BraveSearchBackend.secretID))
        case "searxng":
            fields.append(draftText(environment, group.appending("searxng"), "Instance URL",
                                    "e.g. https://searx.example.org", saved: settings.document.searxngURL) {
                settings.setSearxngURL($0)
            })
        default: break
        }
        return fields
    }

    // MARK: - Images

    static let imagePresets: [(label: String, url: String)] = [
        ("Together AI", "https://api.together.xyz/v1"),
        ("Fireworks", "https://api.fireworks.ai/inference/v1"),
        ("DeepInfra", "https://api.deepinfra.com/v1/openai"),
    ]

    static func imageFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let settings = environment.mediaSettingsStore
        let secrets = environment.secrets
        let choices: [ProviderChoice] = [
            .init(id: "openai", label: "OpenAI Images", secretID: OpenAIImageBackend.secretID),
            .init(id: "pollinations", label: "Pollinations (keyless)", secretID: nil),
            .init(id: "localsd", label: "Local Stable Diffusion (keyless)", secretID: nil),
            .init(id: "stability", label: "Stability AI", secretID: StabilityImageBackend.secretID),
            .init(id: "replicate", label: "Replicate", secretID: ReplicateImageBackend.secretID),
            .init(id: "google", label: "Google Imagen", secretID: GoogleImagenBackend.secretID),
            .init(id: "huggingface", label: "Hugging Face", secretID: HuggingFaceImageBackend.secretID),
            .init(id: "custom", label: "Custom (OpenAI-compatible)", secretID: CustomOpenAIImageBackend.secretID),
        ]
        let doc = settings.document
        let choice = choices.first { $0.id == doc.provider } ?? choices[0]
        let hasKey = choice.secretID.map { !(secrets.secret(for: $0) ?? "").isEmpty } ?? true
        let help: String = switch choice.id {
        case "pollinations": "No key required — images with zero setup."
        case "localsd": setupHelp(!doc.localSDURL.isEmpty, "a server URL",
                                  otherwise: "A local Automatic1111 / ComfyUI server. No key or card.")
        case "custom": setupHelp(hasKey && !doc.customBaseURL.isEmpty, "a base URL and an API key",
                                 otherwise: "Any OpenAI-compatible image endpoint.")
        default: setupHelp(hasKey, "an API key", otherwise: "Leave Model blank for the provider's default.")
        }
        var fields = [providerRow(group.appending("provider"), label: "Image provider", help: help, choices: choices,
                                  current: { settings.document.provider },
                                  set: { settings.setProvider($0); environment.settingsDrafts.text = [:] },
                                  fallback: "openai")]
        if choice.id == "custom" {
            fields.append(draftText(environment, group.appending("base-url"), "Base URL",
                                    "The provider's OpenAI-compatible endpoint.", saved: doc.customBaseURL) {
                settings.setCustomBaseURL($0)
            })
            fields.append(presetRow(group.appending("preset"), imagePresets,
                                    current: { settings.document.customBaseURL }) {
                settings.setCustomBaseURL($0)
                environment.settingsDrafts.text[group.appending("base-url").segments.joined(separator: ".")] = $0
            })
        }
        if choice.id == "localsd" {
            fields.append(draftText(environment, group.appending("local"), "Server URL",
                                    "e.g. http://127.0.0.1:7860", saved: doc.localSDURL) { settings.setLocalSDURL($0) })
        }
        if let secretID = choice.secretID {
            fields.append(keyRow(environment, group.appending("key"), secretID: secretID))
            let modelHint: String = switch choice.id {
            case "openai": "gpt-image-1"
            case "stability": "stable-diffusion-xl-1024-v1-0"
            case "replicate": "black-forest-labs/flux-schnell"
            case "google": "imagen-3.0-generate-002"
            case "huggingface": "black-forest-labs/FLUX.1-schnell"
            default: "the provider's model id"
            }
            fields.append(draftText(environment, group.appending("model"), "Model", "e.g. \(modelHint)",
                                    saved: doc.model) { settings.setModel($0) })
            if choice.id == "openai" || choice.id == "custom" {
                fields.append(draftText(environment, group.appending("size"), "Size", "e.g. 1024x1024",
                                        saved: doc.imageSize) { settings.setImageSize($0.isEmpty ? "1024x1024" : $0) })
            }
        }
        return fields
    }

    // MARK: - Video

    static func videoFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let settings = environment.settingsDrafts.video(environment.persistence)
        let secrets = environment.secrets
        let choices: [ProviderChoice] = [
            .init(id: "replicate", label: "Replicate", secretID: ReplicateVideoBackend.secretID),
            .init(id: "luma", label: "Luma Dream Machine", secretID: LumaVideoBackend.secretID),
            .init(id: "fal", label: "fal.ai", secretID: FalVideoBackend.secretID),
            .init(id: "custom", label: "Custom (Replicate-compatible)", secretID: CustomVideoBackend.secretID),
            .init(id: "local", label: "Local server (keyless)", secretID: nil),
        ]
        let doc = settings.document
        let choice = choices.first { $0.id == doc.provider } ?? choices[0]
        let hasKey = choice.secretID.map { !(secrets.secret(for: $0) ?? "").isEmpty } ?? true
        let help: String = switch choice.id {
        case "local": setupHelp(!doc.localURL.isEmpty, "a server URL",
                                otherwise: "POST {\"prompt\"} → JSON with a video link. No key or card.")
        case "custom": setupHelp(hasKey && !doc.customBaseURL.isEmpty, "a base URL and an API key",
                                 otherwise: "Any Replicate-compatible endpoint.")
        default: setupHelp(hasKey, "an API key", otherwise: "Set Model to reach more models (Pika, Kling, LTX, SVD, …).")
        }
        var fields = [providerRow(group.appending("provider"), label: "Video provider", help: help, choices: choices,
                                  current: { settings.document.provider },
                                  set: { settings.setProvider($0); environment.settingsDrafts.text = [:] },
                                  fallback: "replicate")]
        if choice.id == "local" {
            fields.append(draftText(environment, group.appending("local"), "Server URL",
                                    "e.g. http://127.0.0.1:8000/generate", saved: doc.localURL) { settings.setLocalURL($0) })
            return fields
        }
        if choice.id == "custom" {
            fields.append(draftText(environment, group.appending("base-url"), "Base URL",
                                    "e.g. https://api.provider.com/v1/predictions", saved: doc.customBaseURL) {
                settings.setCustomBaseURL($0)
            })
        }
        if let secretID = choice.secretID {
            fields.append(keyRow(environment, group.appending("key"), secretID: secretID))
        }
        if choice.id != "luma" {
            let hint = choice.id == "fal" ? "fal-ai/ltx-video" : choice.id == "custom" ? "optional model id" : "lightricks/ltx-video"
            fields.append(draftText(environment, group.appending("model"), "Model", "e.g. \(hint)",
                                    saved: doc.model) { settings.setModel($0) })
        }
        return fields
    }

    static func presetRow(_ path: SettingsPath, _ presets: [(label: String, url: String)],
                          current: @escaping () -> String, set: @escaping (String) -> Void) -> SettingsField {
        SettingsField(
            path: path, label: "Endpoint preset", help: "Fills in the base URL for a known provider.",
            keywords: ["endpoint", "preset"] + presets.map { $0.label.lowercased() },
            kind: .select(options: [SettingsOption(id: "", title: "Custom")]
                            + presets.map { SettingsOption(id: $0.url, title: $0.label) },
                          selection: Binding(get: { presets.first { $0.url == current() }?.url ?? "" },
                                             set: { if !$0.isEmpty { set($0) } })))
    }
}
