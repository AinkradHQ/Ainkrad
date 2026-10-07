import AinkradHostRuntime
import Foundation
import Observation

/// M7 Slice 8 (Voice) facade: composes the on-device + provider transcription
/// backends behind `TranscriptionBackendSelector`, then wires the push-to-talk
/// and file-transcription flows on top. `AppEnvironment` owns exactly one
/// instance; `attachSession(_:)` connects it to the live `AgentSession` after
/// both exist (voice auto-send is not a privileged channel — it goes through
/// the same `AgentSession.send` path as typed input).
@MainActor
@Observable
final class VoiceService {
    let settings: VoiceSettingsStore
    let pushToTalk: PushToTalkController
    let fileCoordinator: FileTranscriptionCoordinator
    var reviewTranscript: String?
    var lastNotice: String?

    init(
        persistence: PersistenceStore,
        connections: ConnectionStore,
        http: DataHTTPClient = URLSessionDataHTTPClient(),
        capture: AudioCaptureSession = AVAudioEngineCaptureSession(),
        permission: MicPermissionProviding = SystemMicPermission(),
        availability: SpeechRecognizerAvailability = AppleSpeechAvailability(),
        slicer: AudioSlicer = AVAudioSlicer()
    ) {
        let settings = VoiceSettingsStore(persistence: persistence)
        self.settings = settings

        let onDevice = OnDeviceTranscriptionBackend(availability: availability)
        let providerFactory: () -> TranscriptionService? = { [weak settings] in
            guard let settings, let id = settings.document.providerConnectionID else { return nil }
            return ProviderTranscriptionBackend(
                http: http, connections: connections,
                connectionID: id, model: settings.document.providerModel)
        }
        let selector = TranscriptionBackendSelector(
            settings: settings, onDevice: onDevice,
            providerFactory: providerFactory, availability: availability)

        self.pushToTalk = PushToTalkController(
            settings: settings, capture: capture, permission: permission, selector: selector)
        self.fileCoordinator = FileTranscriptionCoordinator(selector: selector, slicer: slicer)

        pushToTalk.onTranscript = { [weak self] in self?.reviewTranscript = $0 }
        pushToTalk.onNotice = { [weak self] in self?.lastNotice = $0 }
    }

    /// Wire auto-send through the normal Sage path — voice is not privileged.
    func attachSession(_ session: AgentSession) {
        pushToTalk.onAutoSend = { session.send($0) }
    }
}
