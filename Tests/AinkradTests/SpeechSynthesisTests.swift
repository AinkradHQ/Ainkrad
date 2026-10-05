import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("SpeechSynthesis")
struct SpeechSynthesisTests {
    private struct AudioHTTP: DataHTTPClient {
        let bytes: [UInt8]
        let status: Int
        init(bytes: [UInt8], status: Int = 200) {
            self.bytes = bytes
            self.status = status
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(bytes), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
    private func keyed(_ id: String) -> InMemorySecretStore {
        let s = InMemorySecretStore()
        s.setSecret("k", for: id)
        return s
    }
    private let mp3: [UInt8] = [0x49, 0x44, 0x33, 0x04]  // "ID3"

    @Test func openAINotConfiguredWithoutKey() {
        #expect(OpenAITTSBackend(secrets: InMemorySecretStore(), http: AudioHTTP(bytes: [])).isConfigured == false)
    }
    @Test func openAIReturnsAudio() async throws {
        let backend = OpenAITTSBackend(secrets: keyed(OpenAITTSBackend.secretID), http: AudioHTTP(bytes: mp3))
        #expect(try await backend.synthesize("hi") == Data(mp3))
    }
    @Test func openAIErrorThrows() async {
        let backend = OpenAITTSBackend(
            secrets: keyed(OpenAITTSBackend.secretID), http: AudioHTTP(bytes: [], status: 401))
        await #expect(throws: ToolError.self) { _ = try await backend.synthesize("hi") }
    }
    @Test func elevenLabsDefaultsVoiceAndReturnsAudio() async throws {
        let backend = ElevenLabsTTSBackend(secrets: keyed(ElevenLabsTTSBackend.secretID), http: AudioHTTP(bytes: mp3))
        #expect(backend.voiceID == "21m00Tcm4TlvDq8ikWAM")  // default Rachel
        #expect(try await backend.synthesize("hi") == Data(mp3))
    }

    // MARK: Routing selection (pure)

    private func makeRouter() -> RoutingSpeechSynthesizer {
        struct NoopSynth: SpeechSynthesizing { func speak(_ text: String) {} }
        struct NoopPlayer: AudioPlaying { func play(_ data: Data) {} }
        return RoutingSpeechSynthesizer(
            persistence: InMemoryPersistenceStore(), secrets: InMemorySecretStore(),
            onDevice: NoopSynth(), http: AudioHTTP(bytes: []), player: NoopPlayer())
    }

    @Test func onDeviceHasNoCloudBackend() {
        let r = makeRouter()
        #expect(r.cloudBackend(for: SpeechSynthesisSettingsDocument(provider: "onDevice")) == nil)
    }
    @Test func selectsCloudBackends() {
        let r = makeRouter()
        #expect(r.cloudBackend(for: SpeechSynthesisSettingsDocument(provider: "openai")) is OpenAITTSBackend)
        #expect(r.cloudBackend(for: SpeechSynthesisSettingsDocument(provider: "elevenlabs")) is ElevenLabsTTSBackend)
    }
}

@Suite("SpeechSynthesisSettingsStore")
@MainActor
struct SpeechSynthesisSettingsStoreTests {
    @Test func persists() {
        let p = InMemoryPersistenceStore()
        let s = SpeechSynthesisSettingsStore(persistence: p)
        s.setProvider("elevenlabs")
        s.setElevenLabsVoiceID("voice123")
        s.setOpenAIVoice("nova")
        let reloaded = SpeechSynthesisSettingsStore(persistence: p)
        #expect(reloaded.document.provider == "elevenlabs")
        #expect(reloaded.document.elevenLabsVoiceID == "voice123")
        #expect(reloaded.document.openAIVoice == "nova")
    }
}
