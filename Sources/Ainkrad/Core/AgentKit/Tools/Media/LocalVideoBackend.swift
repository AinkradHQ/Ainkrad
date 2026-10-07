import AinkradHostRuntime
import Foundation

/// Keyless local text-to-video backend for a self-hosted server. No key, no card —
/// configuration is just the server URL. Contract (kept deliberately simple so a
/// thin ComfyUI/wrapper can satisfy it): `POST <url>` with `{"prompt": ...}` →
/// JSON containing a video link at `video_url`, `url`, or `output` (string or
/// array). The link is then downloaded. `isConfigured == false` with no URL.
struct LocalVideoBackend: VideoBackend {
    let serverURL: String
    let http: DataHTTPClient

    var isConfigured: Bool { !normalized.isEmpty }

    private var normalized: String {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func generateVideo(prompt: String) async throws -> GeneratedVideo {
        let base = normalized
        guard !base.isEmpty, let url = URL(string: base) else {
            throw ToolError.message("Video generation is not configured.")
        }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("video_generate got HTTP \(response.statusCode) from the local server.")
        }
        guard let videoURL = Self.videoURL(in: data), let dl = URL(string: videoURL) else {
            throw ToolError.message("Local server response contained no video URL.")
        }
        let (bytes, dlResp) = try await http.data(for: URLRequest(url: dl, timeoutInterval: 120))
        guard (200..<300).contains(dlResp.statusCode), !bytes.isEmpty else {
            throw ToolError.message("Failed to download the local video (HTTP \(dlResp.statusCode)).")
        }
        return GeneratedVideo(data: bytes, fileExtension: MediaFileExtension.forURL(videoURL, default: "mp4"))
    }

    /// Extracts a video URL from `video_url`, `url`, or `output` (string/array).
    static func videoURL(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let s = root["video_url"] as? String { return s }
        if let s = root["url"] as? String { return s }
        if let s = root["output"] as? String { return s }
        if let arr = root["output"] as? [Any], let s = arr.first as? String { return s }
        return nil
    }
}
