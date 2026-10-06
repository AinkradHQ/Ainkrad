import AinkradHostRuntime
import Foundation

/// Replicate text-to-video backend. Token in the Keychain via SecretStore. Runs
/// a video model synchronously via `Prefer: wait`, then downloads the resulting
/// video URL. Reuses `ReplicateImageBackend.firstOutputURL` for the flexible
/// `output` shape (string or array of strings).
struct ReplicateVideoBackend: VideoBackend {
    static let secretID = "media.replicate.apiKey"  // shared with the image backend
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    /// `owner/name` of a text-to-video model.
    var model: String = "lightricks/ltx-video"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    func generateVideo(prompt: String) async throws -> GeneratedVideo {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Video generation is not configured.")
        }
        guard let url = URL(string: "https://api.replicate.com/v1/models/\(model)/predictions") else {
            throw ToolError.message("Invalid Replicate URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("wait", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": ["prompt": prompt]])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("video_generate got HTTP \(response.statusCode) from Replicate.")
        }
        guard let videoURL = ReplicateImageBackend.firstOutputURL(in: data), let dl = URL(string: videoURL) else {
            throw ToolError.message("Replicate response contained no video URL.")
        }
        let (bytes, dlResp) = try await http.data(for: URLRequest(url: dl, timeoutInterval: 120))
        guard (200..<300).contains(dlResp.statusCode), !bytes.isEmpty else {
            throw ToolError.message("Failed to download the Replicate video (HTTP \(dlResp.statusCode)).")
        }
        return GeneratedVideo(data: bytes, fileExtension: MediaFileExtension.forURL(videoURL, default: "mp4"))
    }
}
