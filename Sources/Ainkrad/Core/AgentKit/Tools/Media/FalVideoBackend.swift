import Foundation
import AinkradHostRuntime

/// fal.ai text-to-video backend (queue API). Key in the Keychain via SecretStore.
/// Submits to the queue, polls the status URL until `COMPLETED`, then fetches the
/// response URL and extracts the video link. Parsing is isolated for unit tests.
struct FalVideoBackend: VideoBackend {
    static let secretID = "media.fal.apiKey"
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    /// The fal model id to run, e.g. `fal-ai/ltx-video`.
    var model = "fal-ai/ltx-video"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    func generateVideo(prompt: String) async throws -> GeneratedVideo {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Video generation is not configured.")
        }
        // 1. Submit to the queue.
        guard let submitURL = URL(string: "https://queue.fal.run/\(model)") else {
            throw ToolError.message("Invalid fal URL.")
        }
        var submit = URLRequest(url: submitURL, timeoutInterval: 60)
        submit.httpMethod = "POST"
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        submit.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt])
        let (submitData, submitResp) = try await http.data(for: submit)
        guard (200..<300).contains(submitResp.statusCode) else {
            throw ToolError.message("video_generate got HTTP \(submitResp.statusCode) from fal.")
        }
        guard let urls = Self.queueURLs(in: submitData) else {
            throw ToolError.message("fal did not return queue URLs.")
        }
        // 2. Poll the status URL until COMPLETED.
        guard let statusURL = URL(string: urls.statusURL) else {
            throw ToolError.message("fal returned an invalid status URL.")
        }
        _ = try await VideoJobPolling.poll { [http] in
            var poll = URLRequest(url: statusURL, timeoutInterval: 60)
            poll.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await http.data(for: poll)
            return try Self.pollStatus(in: data)
        }
        // 3. Fetch the response payload and extract the video URL.
        guard let responseURL = URL(string: urls.responseURL) else {
            throw ToolError.message("fal returned an invalid response URL.")
        }
        var responseReq = URLRequest(url: responseURL, timeoutInterval: 60)
        responseReq.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        let (responseData, _) = try await http.data(for: responseReq)
        guard let videoURLString = Self.videoURL(in: responseData),
              let videoURL = URL(string: videoURLString) else {
            throw ToolError.message("fal response contained no video URL.")
        }
        // 4. Download.
        let (bytes, dlResp) = try await http.data(for: URLRequest(url: videoURL, timeoutInterval: 120))
        guard (200..<300).contains(dlResp.statusCode), !bytes.isEmpty else {
            throw ToolError.message("Failed to download the fal video (HTTP \(dlResp.statusCode)).")
        }
        return GeneratedVideo(data: bytes, fileExtension: MediaFileExtension.forURL(videoURLString, default: "mp4"))
    }

    // MARK: - Parsing (pure, testable)

    static func queueURLs(in data: Data) -> (statusURL: String, responseURL: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["status_url"] as? String,
              let response = root["response_url"] as? String else { return nil }
        return (status, response)
    }

    /// fal queue status: `IN_QUEUE`/`IN_PROGRESS` → pending, `COMPLETED` → done.
    static func pollStatus(in data: Data) throws -> VideoJobPolling.Status {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .pending }
        switch root["status"] as? String {
        case "COMPLETED": return .done("ready") // sentinel; response URL fetched separately
        case "FAILED", "ERROR": throw ToolError.message("fal generation failed.")
        default: return .pending
        }
    }

    /// Extracts the video URL from a fal result payload: `{ "video": { "url": ... } }`
    /// or a top-level `{ "url": ... }`.
    static func videoURL(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let video = root["video"] as? [String: Any], let url = video["url"] as? String { return url }
        if let url = root["url"] as? String { return url }
        return nil
    }
}
