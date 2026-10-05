import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("PushToTalkController")
@MainActor
struct PushToTalkControllerTests {
    private struct EchoService: TranscriptionService {
        func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
            TranscriptionResult(text: "transcribed")
        }
    }

    private func make(
        mode: PushToTalkMode = .hold, autoSend: Bool = false,
        mic: MicAuthorization = .authorized, grant: Bool = true
    )
        -> (PushToTalkController, FakeCaptureSession)
    {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(mode)
        settings.setAutoSend(autoSend)
        let capture = FakeCaptureSession()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: EchoService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let controller = PushToTalkController(
            settings: settings, capture: capture,
            permission: FakeMicPermission(status: mic, grantOnRequest: grant),
            selector: selector, readAudio: { _ in Data("A".utf8) })
        return (controller, capture)
    }

    private struct AlwaysAvailable: SpeechRecognizerAvailability {
        func isAvailable(localeIdentifier: String) -> Bool { true }
    }

    /// A mic-permission fake whose `request()` stays in flight until manually resolved,
    /// so tests can control the exact interleaving of press/release vs. grant resolution.
    /// `waitUntilRequested()` only returns once the grant continuation is actually stored,
    /// so `resolveRequest(granted:)` is guaranteed to resume a live continuation — no blind
    /// `Task.yield()` guessing, and no risk of resolving before anyone is listening (which
    /// would leak the continuation and hang the caller forever).
    private final class DeferredMicPermission: MicPermissionProviding, @unchecked Sendable {
        private(set) var status: MicAuthorization = .notDetermined
        private var grantContinuation: CheckedContinuation<Bool, Never>?
        private var requestedContinuation: CheckedContinuation<Void, Never>?
        private var hasBeenRequested = false

        func request() async -> Bool {
            await withCheckedContinuation { cont in
                self.grantContinuation = cont
                self.hasBeenRequested = true
                self.requestedContinuation?.resume()
                self.requestedContinuation = nil
            }
        }

        /// Suspends until `request()` has been called and its continuation is live.
        func waitUntilRequested() async {
            if hasBeenRequested { return }
            await withCheckedContinuation { self.requestedContinuation = $0 }
        }

        func resolveRequest(granted: Bool) {
            status = granted ? .authorized : .denied
            grantContinuation?.resume(returning: granted)
            grantContinuation = nil
        }
    }

    @Test func holdRecordsWhilePressed() async {
        let (c, capture) = make(mode: .hold)
        var review: String?
        c.onTranscript = { review = $0 }
        c.pressStarted()
        #expect(capture.isRecording)
        #expect(c.status == .recording)
        c.pressEnded()
        await c.awaitPendingForTesting()
        #expect(!capture.isRecording)
        #expect(review == "transcribed")
        #expect(c.status == .idle)
    }

    @Test func toggleStartsThenStops() async {
        let (c, capture) = make(mode: .toggle)
        c.pressStarted()  // start
        #expect(capture.isRecording)
        c.pressEnded()  // ignored in toggle
        #expect(capture.isRecording)
        c.pressStarted()  // stop + transcribe
        await c.awaitPendingForTesting()
        #expect(!capture.isRecording)
    }

    @Test func autoSendRoutesToSendSink() async {
        let (c, _) = make(mode: .hold, autoSend: true)
        var sent: String?
        c.onAutoSend = { sent = $0 }
        c.pressStarted()
        c.pressEnded()
        await c.awaitPendingForTesting()
        #expect(sent == "transcribed")
    }

    @Test func micDeniedRaisesPermissionNeeded() async {
        let (c, capture) = make(mic: .denied, grant: false)
        var needed = false
        c.onPermissionNeeded = { needed = true }
        c.pressStarted()
        await c.awaitPendingForTesting()
        #expect(needed)
        #expect(!capture.isRecording)
    }

    @Test func interruptionStopsAndTranscribesPartial() async {
        let (c, capture) = make(mode: .hold)
        var review: String?
        c.onTranscript = { review = $0 }
        c.pressStarted()
        c.handleInterruption()
        await c.awaitPendingForTesting()
        #expect(!capture.isRecording)
        #expect(review == "transcribed")
    }

    @Test(.timeLimit(.minutes(1)))
    func holdReleaseBeforeGrantNeverStartsCapture() async {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(.hold)
        let capture = FakeCaptureSession()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: EchoService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let mic = DeferredMicPermission()
        let c = PushToTalkController(
            settings: settings, capture: capture, permission: mic,
            selector: selector, readAudio: { _ in Data("A".utf8) })
        var transcript: String?
        c.onTranscript = { transcript = $0 }

        c.pressStarted()  // notDetermined -> spawns permission-request Task
        await mic.waitUntilRequested()  // deterministic: grant continuation is now live
        c.pressEnded()  // released BEFORE the grant resolves
        mic.resolveRequest(granted: true)  // grant arrives after release
        await c.awaitPendingForTesting()

        #expect(!capture.isRecording)
        #expect(transcript == nil)
        #expect(c.status == .idle)
    }

    // MARK: - C1: temp `.caf` cleanup

    @Test func stopAndTranscribeDeletesTempFileOnSuccess() async throws {
        let (c, capture) = make(mode: .hold)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptt-\(UUID().uuidString).caf")
        try Data("audio".utf8).write(to: tmp)
        capture.producedURL = tmp
        #expect(FileManager.default.fileExists(atPath: tmp.path))

        c.pressStarted()
        c.pressEnded()
        await c.awaitPendingForTesting()

        #expect(!FileManager.default.fileExists(atPath: tmp.path))
    }

    private struct FailingService: TranscriptionService {
        func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
            throw TranscriptionError.provider("boom")
        }
    }

    @Test func stopAndTranscribeDeletesTempFileOnFailure() async throws {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(.hold)
        let capture = FakeCaptureSession()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptt-\(UUID().uuidString).caf")
        try Data("audio".utf8).write(to: tmp)
        capture.producedURL = tmp
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: FailingService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let c = PushToTalkController(
            settings: settings, capture: capture,
            permission: FakeMicPermission(status: .authorized, grantOnRequest: true),
            selector: selector, readAudio: { _ in Data("A".utf8) })

        c.pressStarted()
        c.pressEnded()
        await c.awaitPendingForTesting()

        #expect(!FileManager.default.fileExists(atPath: tmp.path))
        if case .failed = c.status {} else { Issue.record("expected .failed, got \(c.status)") }
    }

    @Test func cancelDeletesTempFile() throws {
        let (c, capture) = make(mode: .hold)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptt-\(UUID().uuidString).caf")
        try Data("audio".utf8).write(to: tmp)
        capture.producedURL = tmp

        c.pressStarted()
        #expect(capture.isRecording)
        c.cancel()

        #expect(!FileManager.default.fileExists(atPath: tmp.path))
        #expect(c.status == .idle)
    }

    // MARK: - C2: cancel() cancels in-flight transcription

    /// A transcription service that suspends until the test resolves it —
    /// lets the test deterministically land `cancel()` while status is
    /// `.transcribing`, then verify the eventual (late) result never reaches
    /// `onTranscript`/`onAutoSend`. Same continuation-gate idiom as
    /// `DeferredMicPermission` above.
    private final class DeferredTranscriptionService: TranscriptionService, @unchecked Sendable {
        private var resultContinuation: CheckedContinuation<String, Never>?
        private var startedContinuation: CheckedContinuation<Void, Never>?
        private var hasStarted = false

        func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
            hasStarted = true
            startedContinuation?.resume()
            startedContinuation = nil
            let text = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                self.resultContinuation = cont
            }
            return TranscriptionResult(text: text)
        }

        func waitUntilStarted() async {
            if hasStarted { return }
            await withCheckedContinuation { self.startedContinuation = $0 }
        }

        func resolve(text: String) {
            resultContinuation?.resume(returning: text)
            resultContinuation = nil
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelDuringTranscribingDoesNotDeliverTranscript() async {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(.hold)
        let capture = FakeCaptureSession()
        let slow = DeferredTranscriptionService()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: slow,
            providerFactory: { nil }, availability: AlwaysAvailable())
        let c = PushToTalkController(
            settings: settings, capture: capture,
            permission: FakeMicPermission(status: .authorized, grantOnRequest: true),
            selector: selector, readAudio: { _ in Data("A".utf8) })
        var review: String?
        var sent: String?
        c.onTranscript = { review = $0 }
        c.onAutoSend = { sent = $0 }

        c.pressStarted()
        c.pressEnded()
        await slow.waitUntilStarted()
        #expect(c.status == .transcribing)

        c.cancel()
        #expect(c.status == .idle)

        slow.resolve(text: "late result")
        // Let the now-orphaned (cancelled) task actually resume and hit its
        // cancellation guard — same actor (MainActor) as this test, so a few
        // yields are enough to flush it; `.timeLimit` above is the hard backstop.
        for _ in 0..<20 { await Task.yield() }

        #expect(review == nil)
        #expect(sent == nil)
        #expect(c.status == .idle)
    }

    @Test(.timeLimit(.minutes(1)))
    func holdGrantResolvesWhileStillHeldStartsCapture() async {
        let settings = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        settings.setMode(.hold)
        let capture = FakeCaptureSession()
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: EchoService(),
            providerFactory: { nil }, availability: AlwaysAvailable())
        let mic = DeferredMicPermission()
        let c = PushToTalkController(
            settings: settings, capture: capture, permission: mic,
            selector: selector, readAudio: { _ in Data("A".utf8) })

        c.pressStarted()  // notDetermined -> spawns permission-request Task
        await mic.waitUntilRequested()  // deterministic: grant continuation is now live
        mic.resolveRequest(granted: true)  // grant arrives while the key is still held
        await c.awaitPendingForTesting()

        #expect(capture.isRecording)
        #expect(c.status == .recording)
    }
}
