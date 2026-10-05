import AVFoundation
import Foundation

protocol AudioCaptureSession: AnyObject {
    var isRecording: Bool { get }
    func start() throws
    func stop() -> URL?
}

/// Records the default input to a temp file via AVAudioEngine. Real capture is
/// manual/screenshot-gated (needs mic entitlement + a device).
final class AVAudioEngineCaptureSession: AudioCaptureSession {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private(set) var isRecording = false
    private var url: URL?

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptt-\(UUID().uuidString).caf")
        self.url = target
        self.file = try AVAudioFile(forWriting: target, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> URL? {
        guard isRecording else { return url }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        isRecording = false
        return url
    }
}
