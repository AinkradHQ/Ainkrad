import Foundation

/// A generated video: raw container bytes + a file extension (mp4/webm/mov).
/// Unlike images, videos are stored to a file (not a base64 `data:` URL) because
/// clips are large and would bloat the persisted canvas document.
struct GeneratedVideo: Equatable, Sendable {
    let data: Data
    let fileExtension: String
}

/// Pluggable text-to-video provider. `isConfigured == false` drives the graceful
/// "not configured" path in `VideoGenerateTool` (never an error). There is no
/// keyless/card-free video provider (unlike Pollinations for images), so every
/// concrete backend here is key-based.
protocol VideoBackend: Sendable {
    var isConfigured: Bool { get }
    func generateVideo(prompt: String) async throws -> GeneratedVideo
}

/// Shared async-job polling for providers that submit a job then poll for
/// completion (Luma, Runway, fal). Bounded so a stuck job can't hang forever.
enum VideoJobPolling {
    /// Polls `check` until it returns a non-nil URL or `maxAttempts` is reached.
    /// `check` returns `.pending` to keep waiting, `.done(url)` when ready, and
    /// throws on a terminal failure. Sleeps `intervalNanos` between attempts.
    enum Status: Equatable {
        case pending
        case done(String)
    }

    static func poll(
        maxAttempts: Int = 60,
        intervalNanos: UInt64 = 2_000_000_000,
        check: () async throws -> Status
    ) async throws -> String {
        for _ in 0..<maxAttempts {
            if case .done(let url) = try await check() { return url }
            try await Task.sleep(nanoseconds: intervalNanos)
        }
        throw ToolError.message("video_generate timed out waiting for the job to finish.")
    }
}
