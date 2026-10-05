import AVFoundation
import Foundation

protocol AudioSlicer: Sendable {
    func duration(of url: URL) async throws -> Double
    func slice(_ url: URL, chunk: AudioChunker.Chunk) async throws -> Data
}

/// Reads duration + exports a time range via AVFoundation. Real export is
/// manual/screenshot-gated; orchestration is unit-tested through a fake.
struct AVAudioSlicer: AudioSlicer {
    func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    func slice(_ url: URL, chunk: AudioChunker.Chunk) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.provider("Cannot create export session")
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString).m4a")
        export.outputURL = out
        export.outputFileType = .m4a
        let start = CMTime(seconds: chunk.start, preferredTimescale: 600)
        let dur = CMTime(seconds: chunk.duration, preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: start, duration: dur)
        await export.export()
        defer { try? FileManager.default.removeItem(at: out) }
        guard export.status == .completed else {
            throw TranscriptionError.provider("Chunk export failed")
        }
        return try Data(contentsOf: out)
    }
}
