import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct CountingService: TranscriptionService {
    func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
        TranscriptionResult(text: String(decoding: audio, as: UTF8.self))
    }
}
private struct FakeSlicer: AudioSlicer {
    let total: Double
    func duration(of url: URL) async throws -> Double { total }
    func slice(_ url: URL, chunk: AudioChunker.Chunk) async throws -> Data {
        Data("c\(chunk.index)".utf8)
    }
}
private struct AlwaysOn: SpeechRecognizerAvailability {
    func isAvailable(localeIdentifier: String) -> Bool { true }
}

@Suite("FileTranscriptionCoordinator", .timeLimit(.minutes(1)))
@MainActor
struct FileTranscriptionCoordinatorTests {
    private func coordinator(total: Double) -> FileTranscriptionCoordinator {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: CountingService(),
            providerFactory: { nil }, availability: AlwaysOn())
        return FileTranscriptionCoordinator(selector: selector, slicer: FakeSlicer(total: total), maxChunk: 120)
    }

    @Test func joinsChunksAndReportsProgress() async throws {
        let c = coordinator(total: 300)  // → 3 chunks
        var last = 0.0
        let text = try await c.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/x.m4a"), byteCount: 1000
        ) { last = $0 }
        #expect(text == "c0 c1 c2")
        #expect(last == 1.0)
    }

    @Test func rejectsUnsupportedBeforeWork() async {
        let c = coordinator(total: 10)
        await #expect(throws: TranscriptionError.self) {
            _ = try await c.transcribe(fileURL: URL(fileURLWithPath: "/tmp/x.pdf"), byteCount: 10) { _ in }
        }
    }
}
