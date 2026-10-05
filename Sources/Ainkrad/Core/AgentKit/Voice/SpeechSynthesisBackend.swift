import AinkradHostRuntime
import Foundation

/// Cloud text-to-speech provider: turns text into audio bytes (mp3). Distinct
/// from `SpeechSynthesizing` (the fire-and-forget `speak` seam) — this fetches
/// audio to be played by an `AudioPlaying`. `isConfigured == false` falls back
/// to on-device speech rather than erroring.
protocol SpeechSynthesisBackend: Sendable {
    var isConfigured: Bool { get }
    func synthesize(_ text: String) async throws -> Data
}

/// OpenAI text-to-speech (`/v1/audio/speech`). Key in the Keychain via SecretStore.
/// `secretID`/`baseURL` are overridable so the same request shape backs the
/// `custom` (OpenAI-speech-compatible) provider.
struct OpenAITTSBackend: SpeechSynthesisBackend {
    static let secretID = "voice.openai.apiKey"
    /// Secret id for the `custom` OpenAI-speech-compatible provider.
    static let customSecretID = "voice.custom.apiKey"
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var model = "gpt-4o-mini-tts"
    var voice = "alloy"
    var baseURL = "https://api.openai.com/v1"
    var keyID = OpenAITTSBackend.secretID

    private var normalizedBase: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    var isConfigured: Bool { !(secrets.secret(for: keyID) ?? "").isEmpty && !normalizedBase.isEmpty }

    func synthesize(_ text: String) async throws -> Data {
        guard let key = secrets.secret(for: keyID), !key.isEmpty else {
            throw ToolError.message("Text-to-speech is not configured.")
        }
        guard let url = URL(string: normalizedBase + "/audio/speech") else {
            throw ToolError.message("Invalid TTS base URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "voice": voice, "input": text, "response_format": "mp3",
        ])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("speak got HTTP \(response.statusCode) from OpenAI.")
        }
        guard !data.isEmpty else { throw ToolError.message("OpenAI returned no audio.") }
        return data
    }
}

/// ElevenLabs text-to-speech. Key in the Keychain via SecretStore.
struct ElevenLabsTTSBackend: SpeechSynthesisBackend {
    static let secretID = "voice.elevenlabs.apiKey"
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var voiceID: String
    var modelID = "eleven_multilingual_v2"

    /// Default voice ("Rachel") when none configured.
    init(secrets: SecretStore, http: DataHTTPClient, voiceID: String = "") {
        self.secrets = secrets
        self.http = http
        self.voiceID = voiceID.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : voiceID
    }

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    func synthesize(_ text: String) async throws -> Data {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Text-to-speech is not configured.")
        }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else {
            throw ToolError.message("Invalid ElevenLabs voice id.")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model_id": modelID])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("speak got HTTP \(response.statusCode) from ElevenLabs.")
        }
        guard !data.isEmpty else { throw ToolError.message("ElevenLabs returned no audio.") }
        return data
    }
}
