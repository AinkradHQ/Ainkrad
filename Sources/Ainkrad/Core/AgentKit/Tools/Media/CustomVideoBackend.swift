import AinkradHostRuntime
import Foundation

/// "Bring-your-own-endpoint" text-to-video backend for any Replicate-compatible
/// sync API: `POST <baseURL>` with `{"input": {"prompt": ...}}` and
/// `Prefer: wait`, returning `{ "output": <url|[url]> }`, then downloads the
/// video. Base URL + model are user-supplied; key is Keychain-only. Reuses
/// `ReplicateImageBackend.firstOutputURL` for the flexible output shape.
struct CustomVideoBackend: VideoBackend {
    static let secretID = "media.customvideo.apiKey"
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    let baseURL: String
    var model: String

    var isConfigured: Bool {
        !normalized.isEmpty && !(secrets.secret(for: Self.secretID) ?? "").isEmpty
    }

    private var normalized: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func generateVideo(prompt: String) async throws -> GeneratedVideo {
        let base = normalized
        guard !base.isEmpty, let key = secrets.secret(for: Self.secretID), !key.isEmpty, let url = URL(string: base)
        else {
            throw ToolError.message("Video generation is not configured.")
        }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("wait", forHTTPHeaderField: "Prefer")
        var input: [String: Any] = ["prompt": prompt]
        if !model.isEmpty { input["model"] = model }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": input])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("video_generate got HTTP \(response.statusCode) from the custom endpoint.")
        }
        guard let videoURL = ReplicateImageBackend.firstOutputURL(in: data), let dl = URL(string: videoURL) else {
            throw ToolError.message("Custom endpoint returned no video URL.")
        }
        let (bytes, dlResp) = try await http.data(for: URLRequest(url: dl, timeoutInterval: 120))
        guard (200..<300).contains(dlResp.statusCode), !bytes.isEmpty else {
            throw ToolError.message("Failed to download the custom video (HTTP \(dlResp.statusCode)).")
        }
        return GeneratedVideo(data: bytes, fileExtension: MediaFileExtension.forURL(videoURL, default: "mp4"))
    }
}
