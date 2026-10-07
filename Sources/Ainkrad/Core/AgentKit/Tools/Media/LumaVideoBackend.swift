import AinkradHostRuntime
import Foundation

/// Luma Dream Machine text-to-video backend. Key in the Keychain via SecretStore.
/// Async job model: submit a generation, poll until `completed`, then download
/// the asset. The status/URL parsing is isolated in static funcs for unit tests.
struct LumaVideoBackend: VideoBackend {
    static let secretID = "media.luma.apiKey"
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var baseURL = "https://api.lumalabs.ai/dream-machine/v1"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    func generateVideo(prompt: String) async throws -> GeneratedVideo {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Video generation is not configured.")
        }
        // 1. Submit.
        guard let submitURL = URL(string: baseURL + "/generations") else {
            throw ToolError.message("Invalid Luma URL.")
        }
        var submit = URLRequest(url: submitURL, timeoutInterval: 60)
        submit.httpMethod = "POST"
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        submit.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt])
        let (submitData, submitResp) = try await http.data(for: submit)
        guard (200..<300).contains(submitResp.statusCode) else {
            throw ToolError.message("video_generate got HTTP \(submitResp.statusCode) from Luma.")
        }
        guard let id = Self.jobID(in: submitData) else {
            throw ToolError.message("Luma did not return a generation id.")
        }
        // 2. Poll.
        let videoURLString = try await VideoJobPolling.poll { [http] in
            guard let pollURL = URL(string: "\(baseURL)/generations/\(id)") else {
                throw ToolError.message("Invalid Luma generation URL.")
            }
            var poll = URLRequest(url: pollURL, timeoutInterval: 60)
            poll.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await http.data(for: poll)
            return try Self.pollStatus(in: data)
        }
        // 3. Download.
        guard let downloadURL = URL(string: videoURLString) else {
            throw ToolError.message("Luma returned an invalid video URL.")
        }
        let (bytes, dlResp) = try await http.data(for: URLRequest(url: downloadURL, timeoutInterval: 120))
        guard (200..<300).contains(dlResp.statusCode), !bytes.isEmpty else {
            throw ToolError.message("Failed to download the Luma video (HTTP \(dlResp.statusCode)).")
        }
        return GeneratedVideo(data: bytes, fileExtension: MediaFileExtension.forURL(videoURLString, default: "mp4"))
    }

    // MARK: - Parsing (pure, testable)

    static func jobID(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
    }

    /// Maps a Luma poll response to a job status. Throws on `failed`.
    static func pollStatus(in data: Data) throws -> VideoJobPolling.Status {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .pending }
        let state = (root["state"] as? String) ?? ""
        if state == "failed" { throw ToolError.message("Luma generation failed.") }
        if state == "completed", let assets = root["assets"] as? [String: Any],
            let video = assets["video"] as? String
        {
            return .done(video)
        }
        return .pending
    }
}
