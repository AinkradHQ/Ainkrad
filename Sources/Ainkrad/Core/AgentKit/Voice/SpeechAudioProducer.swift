import AVFoundation
import AinkradHostRuntime
import Foundation

/// Produces speech audio as bytes (so it can be saved / downloaded / played),
/// as opposed to `SpeechSynthesizing` which only plays fire-and-forget. Used by
/// `SpeakTool` to render a downloadable audio card in the transcript.
protocol SpeechAudioProducing: Sendable {
    /// Returns audio bytes + file extension for `text`.
    func audio(for text: String) async throws -> (data: Data, ext: String)
}

/// Renders on-device AVSpeech to an audio file (keyless/offline) via
/// `AVSpeechSynthesizer.write`, accumulating PCM buffers into a `.caf` file.
/// A holder class owns the synthesizer for the callback's lifetime and guards
/// against double-resuming the continuation.
struct OnDeviceSpeechAudioProducer: SpeechAudioProducing {
    func audio(for text: String) async throws -> (data: Data, ext: String) {
        let holder = WriteHolder()
        let bytes = try await holder.render(text: text)
        return (bytes, "caf")
    }

    // `@unchecked Sendable`: `file`/`resumed` are touched only from `AVSpeechSynthesizer.write`'s serial callback.
    private final class WriteHolder: @unchecked Sendable {
        private let synth = AVSpeechSynthesizer()
        private var file: AVAudioFile?
        private var resumed = false

        func render(text: String) async throws -> Data {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("tts-\(UUID().uuidString).caf")
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                let utterance = AVSpeechUtterance(string: text)
                self.synth.write(utterance) { [self] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 {
                        finish(tmp: tmp, cont: cont)
                        return
                    }
                    do {
                        if file == nil { file = try AVAudioFile(forWriting: tmp, settings: pcm.format.settings) }
                        try file?.write(from: pcm)
                    } catch { resume(cont: cont, with: .failure(error)) }
                }
            }
        }

        private func finish(tmp: URL, cont: CheckedContinuation<Data, Error>) {
            file = nil  // flush/close
            if let data = try? Data(contentsOf: tmp) {
                try? FileManager.default.removeItem(at: tmp)
                resume(cont: cont, with: .success(data))
            } else {
                resume(cont: cont, with: .failure(ToolError.message("On-device speech produced no audio.")))
            }
        }

        private func resume(cont: CheckedContinuation<Data, Error>, with result: Result<Data, Error>) {
            guard !resumed else { return }
            resumed = true
            cont.resume(with: result)
        }
    }
}

/// Wraps a cloud `SpeechSynthesisBackend` (OpenAI/ElevenLabs/custom) as an audio
/// producer. The bytes are mp3.
struct CloudSpeechAudioProducer: SpeechAudioProducing {
    let backend: any SpeechSynthesisBackend
    func audio(for text: String) async throws -> (data: Data, ext: String) {
        (try await backend.synthesize(text), "mp3")
    }
}

/// Routes `speak` audio production to the provider chosen in Settings, read live
/// from persistence. `onDevice` (default) renders offline; cloud providers fetch
/// mp3. Falls back to on-device if a cloud provider is selected but unconfigured.
struct RoutingSpeechAudioProducer: SpeechAudioProducing {
    let persistence: PersistenceStore
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    let onDevice: any SpeechAudioProducing

    func audio(for text: String) async throws -> (data: Data, ext: String) {
        let doc = persistence.load(SpeechSynthesisSettingsDocument.self) ?? SpeechSynthesisSettingsDocument()
        let router = RoutingSpeechSynthesizer(
            persistence: persistence, secrets: secrets, onDevice: SystemSpeechSynthesizer(),
            http: http, player: SystemAudioPlayer())
        if let backend = router.cloudBackend(for: doc), backend.isConfigured {
            return try await CloudSpeechAudioProducer(backend: backend).audio(for: text)
        }
        return try await onDevice.audio(for: text)
    }
}
