import AinkradHostRuntime
import Foundation

/// A "bring-your-own-endpoint" image backend for any OpenAI-images-compatible
/// API (`POST <baseURL>/images/generations` → `{ data: [{ b64_json }] }`).
/// Base URL and model are user-supplied (Together, Fireworks, DeepInfra,
/// self-hosted, …); the key is Keychain-only. This is how "unlimited providers"
/// works without hardcoding each one.
struct CustomOpenAIImageBackend: MediaBackend {
    static let secretID = "media.custom.apiKey"
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    let baseURL: String
    var model: String
    var size: String

    var isConfigured: Bool {
        !normalizedBase.isEmpty && !(secrets.secret(for: Self.secretID) ?? "").isEmpty && !model.isEmpty
    }

    private var normalizedBase: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private struct Response: Decodable {
        struct Item: Decodable { let b64_json: String? }
        let data: [Item]
    }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        let base = normalizedBase
        guard !base.isEmpty, let key = secrets.secret(for: Self.secretID), !key.isEmpty, !model.isEmpty else {
            throw ToolError.message("Image generation is not configured.")
        }
        guard let url = URL(string: base + "/images/generations") else {
            throw ToolError.message("Custom image endpoint URL is invalid.")
        }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "prompt": prompt, "n": 1, "size": size,
        ])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from the custom endpoint.")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.data.first?.b64_json, !b64.isEmpty else {
            throw ToolError.message("Custom endpoint returned no image data.")
        }
        let sniffed = Data(base64Encoded: b64).map(MediaMime.sniff) ?? "image/png"
        return GeneratedImage(mediaType: sniffed, base64: b64)
    }
}
