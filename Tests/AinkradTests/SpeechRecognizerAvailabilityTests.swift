import Foundation
import Speech
import Testing

@testable import Ainkrad

private struct StubAvailability: SpeechRecognizerAvailability {
    let available: Bool
    func isAvailable(localeIdentifier: String) -> Bool { available }
}

@Suite("OnDeviceTranscriptionBackend availability")
@MainActor
struct SpeechRecognizerAvailabilityTests {
    @Test func unavailableLocaleThrows() async {
        let backend = OnDeviceTranscriptionBackend(availability: StubAvailability(available: false))
        await #expect(throws: TranscriptionError.self) {
            _ = try await backend.transcribe(audio: Data("A".utf8), fileName: "m.m4a", localeIdentifier: "zz-ZZ")
        }
    }
}

/// A recognizer whose `resultHandler` never fires — simulates a wedged
/// `SFSpeechRecognizer.recognitionTask` so C3's timeout backstop can be
/// exercised without the real Speech entitlement or a real hang.
private final class NeverFiringRecognizer: SpeechRecognitionTasking {
    func startRecognition(
        request: SFSpeechURLRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) {
        // Deliberately never calls resultHandler.
    }
}

@Suite("OnDeviceTranscriptionBackend timeout backstop")
@MainActor
struct OnDeviceTranscriptionBackendTimeoutTests {
    /// `.timeLimit` is a hard backstop: swift-testing has no default timeout,
    /// so if the injected-timeout wiring regresses and the continuation never
    /// resumes, this test fails instead of freezing the whole suite.
    @Test(.timeLimit(.minutes(1)))
    func neverFiringRecognizerResolvesWithProviderErrorInsteadOfHanging() async {
        let backend = OnDeviceTranscriptionBackend(
            availability: StubAvailability(available: true),
            timeoutNanos: 10_000_000,  // 10ms — deterministic, no real wait
            recognizerFactory: { _ in NeverFiringRecognizer() })
        do {
            _ = try await backend.transcribe(audio: Data("A".utf8), fileName: "m.m4a", localeIdentifier: "en-US")
            Issue.record("expected the timeout backstop to throw")
        } catch let error as TranscriptionError {
            guard case .provider(let message) = error else {
                Issue.record("expected .provider, got \(error)")
                return
            }
            #expect(message.contains("timed out"))
        } catch {
            Issue.record("expected TranscriptionError, got \(error)")
        }
    }
}
