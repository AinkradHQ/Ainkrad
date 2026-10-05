import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private final class FakeDataHTTPClient: DataHTTPClient, @unchecked Sendable {
    var captured: URLRequest?
    var responseData: Data
    var status: Int
    init(responseData: Data, status: Int = 200) {
        self.responseData = responseData
        self.status = status
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        captured = request
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (responseData, http)
    }
}

@Suite("ProviderTranscriptionBackend")
@MainActor
struct ProviderTranscriptionBackendTests {
    private func connections() -> (ConnectionStore, UUID) {
        let store = ConnectionStore(persistence: InMemoryPersistenceStore(), secrets: InMemorySecretStore())
        let c = store.addConnection(
            preset: ProviderPreset.preset(id: "openai"),
            displayName: "OpenAI", baseURL: "https://api.openai.com/v1", token: "sk-test")
        return (store, c.id)
    }

    @Test func transcribesViaMultipartPost() async throws {
        let (store, id) = connections()
        let http = FakeDataHTTPClient(responseData: Data(#"{"text":"hello world"}"#.utf8))
        let backend = ProviderTranscriptionBackend(http: http, connections: store, connectionID: id, model: "whisper-1")
        let result = try await backend.transcribe(audio: Data("A".utf8), fileName: "m.m4a", localeIdentifier: "en-US")
        #expect(result.text == "hello world")
        #expect(http.captured?.httpMethod == "POST")
        #expect(http.captured?.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(http.captured?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(http.captured?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
    }

    @Test func missingConnectionThrows() async {
        let (store, _) = connections()
        let http = FakeDataHTTPClient(responseData: Data())
        let backend = ProviderTranscriptionBackend(
            http: http, connections: store, connectionID: UUID(), model: "whisper-1")
        await #expect(throws: TranscriptionError.self) {
            _ = try await backend.transcribe(audio: Data(), fileName: "m.m4a", localeIdentifier: nil)
        }
    }

    @Test func nonSuccessStatusThrows() async {
        let (store, id) = connections()
        let http = FakeDataHTTPClient(responseData: Data("nope".utf8), status: 401)
        let backend = ProviderTranscriptionBackend(http: http, connections: store, connectionID: id, model: "whisper-1")
        await #expect(throws: TranscriptionError.self) {
            _ = try await backend.transcribe(audio: Data("A".utf8), fileName: "m.m4a", localeIdentifier: nil)
        }
    }
}
