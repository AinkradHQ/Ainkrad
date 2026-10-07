import AinkradHostRuntime
import Foundation
import Observation

/// Persisted choice of text-to-speech provider for the `speak` tool. Keys are
/// Keychain-only via SecretStore. `onDevice` is the default (keyless/offline).
struct SpeechSynthesisSettingsDocument: PersistableDocument {
    static let documentID = "tts.settings"
    var provider: String = "onDevice"
    /// ElevenLabs voice id (non-secret). Empty → the backend's default voice.
    var elevenLabsVoiceID: String = ""
    /// OpenAI TTS voice name (e.g. "alloy"). Non-secret.
    var openAIVoice: String = "alloy"
    /// Base URL / model / voice for the `custom` OpenAI-speech-compatible provider.
    var customBaseURL: String = ""
    var customModel: String = ""
    var customVoice: String = ""

    init(
        provider: String = "onDevice", elevenLabsVoiceID: String = "", openAIVoice: String = "alloy",
        customBaseURL: String = "", customModel: String = "", customVoice: String = ""
    ) {
        self.provider = provider
        self.elevenLabsVoiceID = elevenLabsVoiceID
        self.openAIVoice = openAIVoice
        self.customBaseURL = customBaseURL
        self.customModel = customModel
        self.customVoice = customVoice
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "onDevice"
        elevenLabsVoiceID = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceID) ?? ""
        openAIVoice = try c.decodeIfPresent(String.self, forKey: .openAIVoice) ?? "alloy"
        customBaseURL = try c.decodeIfPresent(String.self, forKey: .customBaseURL) ?? ""
        customModel = try c.decodeIfPresent(String.self, forKey: .customModel) ?? ""
        customVoice = try c.decodeIfPresent(String.self, forKey: .customVoice) ?? ""
    }
    private enum CodingKeys: String, CodingKey {
        case provider, elevenLabsVoiceID, openAIVoice, customBaseURL, customModel, customVoice
    }
}

@MainActor
@Observable
final class SpeechSynthesisSettingsStore {
    private(set) var document: SpeechSynthesisSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(SpeechSynthesisSettingsDocument.self) ?? SpeechSynthesisSettingsDocument()
    }

    func setProvider(_ id: String) {
        document.provider = id
        persistence.save(document)
    }
    func setElevenLabsVoiceID(_ v: String) {
        document.elevenLabsVoiceID = v
        persistence.save(document)
    }
    func setOpenAIVoice(_ v: String) {
        document.openAIVoice = v
        persistence.save(document)
    }
    func setCustomBaseURL(_ u: String) {
        document.customBaseURL = u
        persistence.save(document)
    }
    func setCustomModel(_ m: String) {
        document.customModel = m
        persistence.save(document)
    }
    func setCustomVoice(_ v: String) {
        document.customVoice = v
        persistence.save(document)
    }
}
