import Foundation
import Speech

/// Guards a `CheckedContinuation` against SFSpeech's `recognitionTask` calling its
/// completion handler more than once (partial results + a final result, or a late
/// error after completion). The handler fires on SFSpeech's private queue, so the
/// guard must be its own lock rather than a captured `var` in the closure.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<TranscriptionResult, Error>

    init(_ continuation: CheckedContinuation<TranscriptionResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: TranscriptionResult) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }
}

/// Seam over `SFSpeechRecognizer.recognitionTask` so tests can inject a stub
/// that never calls its handler (to exercise the timeout backstop below)
/// without touching the real Speech entitlement.
protocol SpeechRecognitionTasking {
    func startRecognition(
        request: SFSpeechURLRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void)
}

extension SFSpeechRecognizer: SpeechRecognitionTasking {
    func startRecognition(
        request: SFSpeechURLRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) {
        _ = recognitionTask(with: request, resultHandler: resultHandler)
    }
}

/// Apple on-device speech recognition. Private + offline — audio never leaves
/// the machine. The availability gate is unit-tested; the recognition path
/// requires the Speech entitlement + a downloaded model and is manual-gated.
struct OnDeviceTranscriptionBackend: TranscriptionService {
    let availability: SpeechRecognizerAvailability
    /// Continuation-resume backstop for a recognizer whose handler never
    /// fires (e.g. a wedged `SFSpeechRecognizer`). Injectable so tests can
    /// exercise the timeout path deterministically instead of waiting out a
    /// real 30s deadline. `ContinuationBox`'s single-resume guard makes racing
    /// this against the real handler safe either way.
    let timeoutNanos: UInt64
    private let recognizerFactory: (Locale) -> SpeechRecognitionTasking?

    init(
        availability: SpeechRecognizerAvailability = AppleSpeechAvailability(),
        timeoutNanos: UInt64 = 30_000_000_000,
        recognizerFactory: @escaping (Locale) -> SpeechRecognitionTasking? = { SFSpeechRecognizer(locale: $0) }
    ) {
        self.availability = availability
        self.timeoutNanos = timeoutNanos
        self.recognizerFactory = recognizerFactory
    }

    func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
        let locale = localeIdentifier ?? "en-US"
        guard availability.isAvailable(localeIdentifier: locale) else {
            throw TranscriptionError.unavailable("On-device speech unavailable for \(locale)")
        }
        guard let recognizer = recognizerFactory(Locale(identifier: locale)) else {
            throw TranscriptionError.unavailable(locale)
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString)-\(fileName)")
        try audio.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let request = SFSpeechURLRecognitionRequest(url: tmp)
        request.requiresOnDeviceRecognition = true

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            recognizer.startRecognition(request: request) { result, error in
                if let error {
                    box.resume(throwing: TranscriptionError.provider(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    box.resume(
                        returning: TranscriptionResult(
                            text: result.bestTranscription.formattedString, isFinal: true))
                }
            }
            // Bounded wait: if the recognizer's handler never fires, resolve
            // with a typed error instead of hanging forever. No-ops (via the
            // box's single-resume guard) once a real result/error already won.
            let timeoutNanos = self.timeoutNanos
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                box.resume(throwing: TranscriptionError.provider("on-device transcription timed out"))
            }
        }
    }
}
