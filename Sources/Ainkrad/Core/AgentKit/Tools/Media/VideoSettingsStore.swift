import AinkradHostRuntime
import Foundation
import Observation

/// Persisted choice of `video_generate` provider. API keys are Keychain-only via
/// SecretStore (each backend's `secretID`), never here.
struct VideoSettingsDocument: PersistableDocument {
    static let documentID = "video.settings"
    var provider: String = "replicate"
    /// Model override for model-parameterized backends (Replicate/fal/custom).
    /// Empty → backend default. Also the "more providers" lever.
    var model: String = ""
    /// Base URL for the `custom` (Replicate-compatible sync) video provider.
    var customBaseURL: String = ""
    /// Base URL for the keyless `local` video server (POST `{prompt}` →
    /// `{video_url|url|output}`, then download).
    var localURL: String = ""

    init(provider: String = "replicate", model: String = "", customBaseURL: String = "", localURL: String = "") {
        self.provider = provider
        self.model = model
        self.customBaseURL = customBaseURL
        self.localURL = localURL
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "replicate"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        customBaseURL = try c.decodeIfPresent(String.self, forKey: .customBaseURL) ?? ""
        localURL = try c.decodeIfPresent(String.self, forKey: .localURL) ?? ""
    }
    private enum CodingKeys: String, CodingKey { case provider, model, customBaseURL, localURL }
}

/// Backs the Sage Settings VIDEO section's provider picker. Mirrors
/// `MediaSettingsStore`.
@MainActor
@Observable
final class VideoSettingsStore {
    private(set) var document: VideoSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(VideoSettingsDocument.self) ?? VideoSettingsDocument()
    }

    func setProvider(_ id: String) {
        document.provider = id
        persistence.save(document)
    }
    func setModel(_ m: String) {
        document.model = m
        persistence.save(document)
    }
    func setCustomBaseURL(_ u: String) {
        document.customBaseURL = u
        persistence.save(document)
    }
    func setLocalURL(_ u: String) {
        document.localURL = u
        persistence.save(document)
    }
}
