import AVFoundation
import AinkradHostRuntime
import Foundation

/// Plays audio bytes (mp3) on the user's machine. Seam so the routing synth is
/// testable without real playback.
protocol AudioPlaying: Sendable {
    func play(_ data: Data)
}

struct SystemAudioPlayer: AudioPlaying {
    // AVAudioPlayer must outlive the call; hold one shared instance, pinned to
    // the main actor (AVAudioPlayer isn't Sendable).
    @MainActor static var current: AVAudioPlayer?
    func play(_ data: Data) {
        MainActor.assumeIsolated {
            Self.current = try? AVAudioPlayer(data: data)
            Self.current?.play()
        }
    }
}

/// `SpeechSynthesizing` that routes the `speak` tool to the provider chosen in
/// Settings, read live from persistence. `onDevice` (default) uses the offline
/// AVSpeech synth; cloud providers fetch audio then play it. `speak` stays
/// fire-and-forget (the tool doesn't await playback); the cloud path runs in a
/// detached Task and silently falls back to on-device if unconfigured or failing.
struct RoutingSpeechSynthesizer: SpeechSynthesizing {
    let persistence: PersistenceStore
    nonisolated(unsafe) let secrets: SecretStore
    let onDevice: any SpeechSynthesizing
    let http: DataHTTPClient
    let player: any AudioPlaying

    func speak(_ text: String) {
        let doc = persistence.load(SpeechSynthesisSettingsDocument.self) ?? SpeechSynthesisSettingsDocument()
        guard let backend = cloudBackend(for: doc), backend.isConfigured else {
            onDevice.speak(text)  // default / not configured → offline
            return
        }
        let player = self.player
        let fallback = self.onDevice
        Task {
            do {
                let audio = try await backend.synthesize(text)
                player.play(audio)
            } catch {
                fallback.speak(text)  // network/provider failure → offline
            }
        }
    }

    /// The cloud backend for the persisted provider, or `nil` for on-device.
    func cloudBackend(for doc: SpeechSynthesisSettingsDocument) -> (any SpeechSynthesisBackend)? {
        switch doc.provider {
        case "openai":
            return OpenAITTSBackend(secrets: secrets, http: http, voice: doc.openAIVoice)
        case "elevenlabs":
            return ElevenLabsTTSBackend(secrets: secrets, http: http, voiceID: doc.elevenLabsVoiceID)
        case "custom":
            return OpenAITTSBackend(
                secrets: secrets, http: http,
                model: doc.customModel.isEmpty ? "tts-1" : doc.customModel,
                voice: doc.customVoice.isEmpty ? "alloy" : doc.customVoice,
                baseURL: doc.customBaseURL,
                keyID: OpenAITTSBackend.customSecretID)
        default:
            return nil
        }
    }
}
