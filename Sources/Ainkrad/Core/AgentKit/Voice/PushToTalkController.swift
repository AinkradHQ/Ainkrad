import Foundation
import Observation

@MainActor
@Observable
final class PushToTalkController {
    enum Status: Equatable {
        case idle, recording, transcribing
        case failed(String)
    }
    private(set) var status: Status = .idle

    var onTranscript: ((String) -> Void)?
    var onAutoSend: ((String) -> Void)?
    var onPermissionNeeded: (() -> Void)?
    var onNotice: ((String) -> Void)?

    private let settings: VoiceSettingsStore
    private let capture: AudioCaptureSession
    private let permission: MicPermissionProviding
    private let selector: TranscriptionBackendSelector
    private let readAudio: (URL) throws -> Data
    private var pending: Task<Void, Never>?
    /// Tracks whether the hold key is currently physically held (hold mode intent).
    private var isPressHeld = false
    /// Guards against spawning a second concurrent mic-permission request.
    private var isRequestingPermission = false

    init(
        settings: VoiceSettingsStore, capture: AudioCaptureSession,
        permission: MicPermissionProviding, selector: TranscriptionBackendSelector,
        readAudio: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.settings = settings
        self.capture = capture
        self.permission = permission
        self.selector = selector
        self.readAudio = readAudio
    }

    func pressStarted() {
        isPressHeld = true
        switch settings.document.mode {
        case .hold:
            beginRecording()
        case .toggle:
            if capture.isRecording { stopAndTranscribe() } else { beginRecording() }
        }
    }

    func pressEnded() {
        isPressHeld = false
        guard settings.document.mode == .hold, capture.isRecording else { return }
        stopAndTranscribe()
    }

    func toggle() {
        if capture.isRecording { stopAndTranscribe() } else { beginRecording() }
    }

    func cancel() {
        isPressHeld = false
        pending?.cancel()
        pending = nil
        if let url = capture.stop() {
            try? FileManager.default.removeItem(at: url)
        }
        status = .idle
    }

    func handleInterruption() {
        isPressHeld = false
        guard capture.isRecording else { return }
        stopAndTranscribe()
    }

    private func beginRecording() {
        guard !capture.isRecording, !isRequestingPermission else { return }
        if permission.status == .authorized {
            startCaptureNow()
            return
        }
        let mode = settings.document.mode
        isRequestingPermission = true
        pending = Task { [weak self] in
            guard let self else { return }
            let granted = await self.permission.request()
            self.isRequestingPermission = false
            guard granted else {
                self.status = .failed("Microphone access denied")
                self.onPermissionNeeded?()
                return
            }
            // Start-after-release race guard: in hold mode, only start capture if the
            // key is still physically held when the grant resolves. In toggle mode the
            // toggle-on intent stands regardless of subsequent (ignored) key events.
            if mode == .hold && !self.isPressHeld {
                return
            }
            self.startCaptureNow()
        }
    }

    private func startCaptureNow() {
        do {
            try capture.start()
            status = .recording
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func stopAndTranscribe() {
        guard let url = capture.stop() else {
            status = .idle
            return
        }
        status = .transcribing
        pending = Task { [weak self] in
            guard let self else { return }
            // Self-cleaning: the recorded `.caf` is scratch space for this one
            // transcription attempt (success, failure, or cancellation) — mirrors
            // AVAudioSlicer.slice's `defer { removeItem }` idiom.
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let resolved = try self.selector.resolve()
                if let notice = resolved.notice { self.onNotice?(notice) }
                let audio = try self.readAudio(url)
                let result = try await resolved.service.transcribe(
                    audio: audio, fileName: url.lastPathComponent,
                    localeIdentifier: self.settings.document.localeIdentifier)
                // Cooperative cancellation: `cancel()` may have fired while this
                // was in flight (and already reset `status` to `.idle`) — don't
                // let a late result resurrect a transcript/auto-send/status after
                // the user cancelled. Mirrors RunManager.stop's `!Task.isCancelled` guard.
                guard !Task.isCancelled else { return }
                if self.settings.document.autoSend {
                    self.onAutoSend?(result.text)
                } else {
                    self.onTranscript?(result.text)
                }
                self.status = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self.status = .failed(String(describing: error))
            }
        }
    }

    /// Test-only: await the most recent start/stop task.
    func awaitPendingForTesting() async { await pending?.value }
}
