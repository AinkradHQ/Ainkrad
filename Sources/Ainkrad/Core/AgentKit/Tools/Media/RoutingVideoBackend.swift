import AinkradHostRuntime
import Foundation

/// Dispatches `video_generate` to the provider selected in Settings, read live
/// from the persisted `VideoSettingsDocument.provider` on every call. All video
/// providers are key-based (no keyless video exists). Defaults to Replicate.
struct RoutingVideoBackend: VideoBackend {
    let persistence: PersistenceStore
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let replicate: ReplicateVideoBackend
    let luma: LumaVideoBackend
    let fal: FalVideoBackend
    /// HTTP client for the custom/local backends, built live from the document.
    let auxHTTP: DataHTTPClient

    private var active: any VideoBackend {
        let doc = persistence.load(VideoSettingsDocument.self) ?? VideoSettingsDocument()
        let model = doc.model.trimmingCharacters(in: .whitespacesAndNewlines)
        switch doc.provider {
        case "luma": return luma
        case "fal":
            var b = fal
            if !model.isEmpty { b.model = model }
            return b
        case "local": return LocalVideoBackend(serverURL: doc.localURL, http: auxHTTP)
        case "custom":
            return CustomVideoBackend(secrets: secrets, http: auxHTTP, baseURL: doc.customBaseURL, model: model)
        default:
            var b = replicate
            if !model.isEmpty { b.model = model }
            return b
        }
    }

    var isConfigured: Bool { active.isConfigured }

    func generateVideo(prompt: String) async throws -> GeneratedVideo {
        try await active.generateVideo(prompt: prompt)
    }
}
