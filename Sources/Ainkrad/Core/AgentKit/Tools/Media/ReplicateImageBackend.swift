import AinkradHostRuntime
import Foundation

/// Replicate image backend. Token in the Keychain via SecretStore, never a
/// document. Runs a model synchronously via the `Prefer: wait` header, then
/// fetches the resulting image URL. `output` may be a single URL string or an
/// array of URL strings depending on the model, so it is parsed leniently.
struct ReplicateImageBackend: MediaBackend {
    static let secretID = "media.replicate.apiKey"
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    /// `owner/name` of a text-to-image model. flux-schnell is fast and cheap.
    var model: String = "black-forest-labs/flux-schnell"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Image generation is not configured.")
        }
        guard let url = URL(string: "https://api.replicate.com/v1/models/\(model)/predictions") else {
            throw ToolError.message("Invalid Replicate URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("wait", forHTTPHeaderField: "Prefer")  // block until finished
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": ["prompt": prompt]])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from Replicate.")
        }
        guard let imageURL = Self.firstOutputURL(in: data) else {
            throw ToolError.message("Replicate response contained no image URL.")
        }
        // Second hop: download the generated image bytes.
        guard let dl = URL(string: imageURL) else {
            throw ToolError.message("Replicate returned an invalid image URL.")
        }
        let (imgData, imgResp) = try await http.data(for: URLRequest(url: dl, timeoutInterval: 60))
        guard (200..<300).contains(imgResp.statusCode), !imgData.isEmpty else {
            throw ToolError.message("Failed to download the Replicate image (HTTP \(imgResp.statusCode)).")
        }
        return GeneratedImage(mediaType: MediaMime.sniff(imgData), base64: imgData.base64EncodedString())
    }

    /// Extracts the first URL from Replicate's `output`, which is either a
    /// String or an array of Strings. Isolated for unit testing.
    static func firstOutputURL(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let s = root["output"] as? String { return s }
        if let arr = root["output"] as? [Any], let s = arr.first as? String { return s }
        return nil
    }
}
