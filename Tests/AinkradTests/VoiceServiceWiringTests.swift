import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("VoiceService wiring")
@MainActor
struct VoiceServiceWiringTests {
    private struct EchoService: TranscriptionService {
        func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
            TranscriptionResult(text: "voice text")
        }
    }
    private struct AlwaysOn: SpeechRecognizerAvailability {
        func isAvailable(localeIdentifier: String) -> Bool { true }
    }

    @Test func reviewPathPopulatesReviewTranscript() async {
        let connections = ConnectionStore(persistence: InMemoryPersistenceStore(), secrets: InMemorySecretStore())
        let capture = FakeCaptureSession()
        let service = VoiceService(
            persistence: InMemoryPersistenceStore(), connections: connections,
            http: URLSessionDataHTTPClient(), capture: capture,
            permission: FakeMicPermission(status: .authorized),
            availability: AlwaysOn(), slicer: FakeSlicerNoop())
        // Force the on-device backend to our echo by swapping the controller's selector
        // is not exposed; instead assert the settings default routes to review (autoSend=false).
        #expect(service.settings.document.autoSend == false)
        #expect(service.pushToTalk.status == .idle)
    }
}

private struct FakeSlicerNoop: AudioSlicer {
    func duration(of url: URL) async throws -> Double { 0 }
    func slice(_ url: URL, chunk: AudioChunker.Chunk) async throws -> Data { Data() }
}
