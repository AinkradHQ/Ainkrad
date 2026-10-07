import AinkradHostRuntime
import Foundation
import Observation

/// Persisted choice of image/media generation provider. The API key itself never
/// lives here — it's Keychain-only via `SecretStore` (`OpenAIImageBackend.secretID`).
struct MediaSettingsDocument: PersistableDocument {
    static let documentID = "media.settings"
    var provider: String = "openai"
    /// Base URL of the local Stable Diffusion server for the keyless `localsd`
    /// provider. Not a credential, so it lives in the document (unlike the API
    /// keys, which are Keychain-only). Empty means that backend is unconfigured.
    var localSDURL: String = ""
    // Full control (all non-secret):
    /// Model / engine override for the active provider. Empty → backend default.
    /// Doubles as "more providers" for model-parameterized backends (Replicate,
    /// Hugging Face, fal): any model id becomes a provider.
    var model: String = ""
    /// Output size for providers that accept it (OpenAI/custom), e.g. "1024x1024".
    var imageSize: String = "1024x1024"
    /// Base URL for the `custom` OpenAI-images-compatible provider.
    var customBaseURL: String = ""

    init(
        provider: String = "openai", localSDURL: String = "", model: String = "",
        imageSize: String = "1024x1024", customBaseURL: String = ""
    ) {
        self.provider = provider
        self.localSDURL = localSDURL
        self.model = model
        self.imageSize = imageSize
        self.customBaseURL = customBaseURL
    }
    // Forward-compatible decode (host idiom): every field tolerates absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "openai"
        localSDURL = try c.decodeIfPresent(String.self, forKey: .localSDURL) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        imageSize = try c.decodeIfPresent(String.self, forKey: .imageSize) ?? "1024x1024"
        customBaseURL = try c.decodeIfPresent(String.self, forKey: .customBaseURL) ?? ""
    }
    private enum CodingKeys: String, CodingKey { case provider, localSDURL, model, imageSize, customBaseURL }
}

/// Backs the Sage Settings MEDIA section's provider picker. Mirrors
/// `WebSearchSettingsStore`: loads the persisted document at init, writes
/// through on every setter call.
@MainActor
@Observable
final class MediaSettingsStore {
    private(set) var document: MediaSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(MediaSettingsDocument.self) ?? MediaSettingsDocument()
    }

    func setProvider(_ id: String) {
        document.provider = id
        persistence.save(document)
    }

    func setLocalSDURL(_ url: String) {
        document.localSDURL = url
        persistence.save(document)
    }

    func setModel(_ m: String) {
        document.model = m
        persistence.save(document)
    }
    func setImageSize(_ s: String) {
        document.imageSize = s
        persistence.save(document)
    }
    func setCustomBaseURL(_ u: String) {
        document.customBaseURL = u
        persistence.save(document)
    }
}
