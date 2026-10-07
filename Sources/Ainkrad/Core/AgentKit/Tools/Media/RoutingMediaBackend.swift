import AinkradHostRuntime
import Foundation

/// Dispatches `image_generate` to the provider the user selected in Settings,
/// read live from the persisted `MediaSettingsDocument` on every call — so
/// switching provider, model, size, or the custom/local URL takes effect without
/// an app relaunch. Applies the doc's `model`/`imageSize` overrides to the active
/// backend (an empty model keeps the backend default). `PersistenceStore` is a
/// plain (non-Sendable) `AnyObject`; `nonisolated(unsafe)` mirrors the
/// `OpenAIImageBackend.secrets` precedent.
struct RoutingMediaBackend: MediaBackend {
    let persistence: PersistenceStore
    nonisolated(unsafe) let secrets: SecretStore
    let openai: OpenAIImageBackend
    let pollinations: PollinationsImageBackend
    let stability: StabilityImageBackend
    let replicate: ReplicateImageBackend
    let google: GoogleImagenBackend
    let huggingface: HuggingFaceImageBackend
    /// HTTP client used to build the local / custom backends on demand (their
    /// config is read live from the document, so they are constructed per call).
    let auxHTTP: DataHTTPClient

    private var document: MediaSettingsDocument {
        persistence.load(MediaSettingsDocument.self) ?? MediaSettingsDocument()
    }

    /// The backend for the currently-persisted provider (defaults to OpenAI),
    /// with the doc's model/size overrides applied.
    private var active: any MediaBackend {
        let doc = document
        let model = doc.model.trimmingCharacters(in: .whitespacesAndNewlines)
        switch doc.provider {
        case "pollinations":
            return pollinations
        case "localsd":
            return LocalStableDiffusionBackend(baseURL: doc.localSDURL, http: auxHTTP)
        case "custom":
            return CustomOpenAIImageBackend(
                secrets: secrets, http: auxHTTP,
                baseURL: doc.customBaseURL, model: model, size: doc.imageSize)
        case "stability":
            var b = stability
            if !model.isEmpty { b.engine = model }
            return b
        case "replicate":
            var b = replicate
            if !model.isEmpty { b.model = model }
            return b
        case "google":
            var b = google
            if !model.isEmpty { b.model = model }
            return b
        case "huggingface":
            var b = huggingface
            if !model.isEmpty { b.model = model }
            return b
        default:
            var b = openai
            if !model.isEmpty { b.model = model }
            b.size = doc.imageSize
            return b
        }
    }

    var isConfigured: Bool { active.isConfigured }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        try await active.generateImage(prompt: prompt)
    }
}
