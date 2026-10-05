import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomProviders")
struct CustomProvidersTests {
    private struct JSONHTTP: DataHTTPClient {
        let json: String
        let status: Int
        init(json: String, status: Int = 200) {
            self.json = json
            self.status = status
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }
    private struct TwoHopHTTP: DataHTTPClient {
        let apiJSON: String
        let bytes: [UInt8]
        let apiHost: String
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let host = request.url?.host ?? ""
            let body = host.contains(apiHost) ? Data(apiJSON.utf8) : Data(bytes)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    private func keyed(_ id: String) -> InMemorySecretStore {
        let s = InMemorySecretStore()
        s.setSecret("k", for: id)
        return s
    }

    // MARK: Custom image

    @Test func customImageConfigRequiresUrlKeyModel() {
        let noKey = CustomOpenAIImageBackend(
            secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}"),
            baseURL: "https://x/v1", model: "m", size: "1024x1024")
        #expect(noKey.isConfigured == false)
        let full = CustomOpenAIImageBackend(
            secrets: keyed(CustomOpenAIImageBackend.secretID), http: JSONHTTP(json: "{}"),
            baseURL: "https://x/v1", model: "m", size: "1024x1024")
        #expect(full.isConfigured)
        let noModel = CustomOpenAIImageBackend(
            secrets: keyed(CustomOpenAIImageBackend.secretID), http: JSONHTTP(json: "{}"),
            baseURL: "https://x/v1", model: "", size: "1024x1024")
        #expect(noModel.isConfigured == false)
    }
    @Test func customImageDecodes() async throws {
        let b = CustomOpenAIImageBackend(
            secrets: keyed(CustomOpenAIImageBackend.secretID),
            http: JSONHTTP(json: #"{"data":[{"b64_json":"QUJD"}]}"#),
            baseURL: "https://x/v1/", model: "m", size: "512x512")
        #expect(try await b.generateImage(prompt: "p").base64 == "QUJD")
    }

    // MARK: Local video (keyless)

    @Test func localVideoNotConfiguredWithoutURL() {
        #expect(LocalVideoBackend(serverURL: "", http: JSONHTTP(json: "{}")).isConfigured == false)
        #expect(LocalVideoBackend(serverURL: "http://127.0.0.1:8000/gen", http: JSONHTTP(json: "{}")).isConfigured)
    }
    @Test func localVideoParsesURLVariants() {
        #expect(LocalVideoBackend.videoURL(in: Data(#"{"video_url":"https://c/a.mp4"}"#.utf8)) == "https://c/a.mp4")
        #expect(LocalVideoBackend.videoURL(in: Data(#"{"url":"https://c/b.mp4"}"#.utf8)) == "https://c/b.mp4")
        #expect(LocalVideoBackend.videoURL(in: Data(#"{"output":["https://c/d.mp4"]}"#.utf8)) == "https://c/d.mp4")
        #expect(LocalVideoBackend.videoURL(in: Data(#"{}"#.utf8)) == nil)
    }
    @Test func localVideoDownloads() async throws {
        let b = LocalVideoBackend(
            serverURL: "http://local.test/gen",
            http: TwoHopHTTP(
                apiJSON: #"{"video_url":"https://cdn.example/v.webm"}"#, bytes: [1, 2, 3], apiHost: "local.test"))
        let v = try await b.generateVideo(prompt: "p")
        #expect(v.data == Data([1, 2, 3]))
        #expect(v.fileExtension == "webm")
    }

    // MARK: Custom video

    @Test func customVideoNotConfigured() {
        #expect(
            CustomVideoBackend(
                secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}"), baseURL: "https://x", model: ""
            ).isConfigured == false)
        #expect(
            CustomVideoBackend(
                secrets: keyed(CustomVideoBackend.secretID), http: JSONHTTP(json: "{}"), baseURL: "https://x", model: ""
            ).isConfigured)
    }

    // MARK: Custom TTS (OpenAI-compatible via keyID/baseURL override)

    @Test func customTTSUsesOverrideKeyAndBase() async throws {
        let b = OpenAITTSBackend(
            secrets: keyed(OpenAITTSBackend.customSecretID), http: JSONHTTP(json: "AUDIO"),
            model: "tts-1", voice: "alloy", baseURL: "https://tts.example/v1",
            keyID: OpenAITTSBackend.customSecretID)
        #expect(b.isConfigured)
        #expect(try await b.synthesize("hi") == Data("AUDIO".utf8))
        // The default-key backend is NOT configured by the custom key.
        #expect(
            OpenAITTSBackend(secrets: keyed(OpenAITTSBackend.customSecretID), http: JSONHTTP(json: "{}")).isConfigured
                == false)
    }

    // MARK: Persistence of new control fields

    @MainActor @Test func mediaControlsPersist() {
        let p = InMemoryPersistenceStore()
        let s = MediaSettingsStore(persistence: p)
        s.setProvider("custom")
        s.setModel("flux")
        s.setImageSize("512x512")
        s.setCustomBaseURL("https://x/v1")
        let r = MediaSettingsStore(persistence: p).document
        #expect(
            r.provider == "custom" && r.model == "flux" && r.imageSize == "512x512" && r.customBaseURL == "https://x/v1"
        )
    }
    @MainActor @Test func videoControlsPersist() {
        let p = InMemoryPersistenceStore()
        let s = VideoSettingsStore(persistence: p)
        s.setProvider("local")
        s.setModel("ltx")
        s.setLocalURL("http://127.0.0.1/gen")
        s.setCustomBaseURL("https://x")
        let r = VideoSettingsStore(persistence: p).document
        #expect(
            r.provider == "local" && r.model == "ltx" && r.localURL == "http://127.0.0.1/gen"
                && r.customBaseURL == "https://x")
    }
    @MainActor @Test func ttsControlsPersist() {
        let p = InMemoryPersistenceStore()
        let s = SpeechSynthesisSettingsStore(persistence: p)
        s.setProvider("custom")
        s.setCustomBaseURL("https://x/v1")
        s.setCustomModel("tts-1")
        s.setCustomVoice("nova")
        let r = SpeechSynthesisSettingsStore(persistence: p).document
        #expect(
            r.provider == "custom" && r.customBaseURL == "https://x/v1" && r.customModel == "tts-1"
                && r.customVoice == "nova")
    }
}
