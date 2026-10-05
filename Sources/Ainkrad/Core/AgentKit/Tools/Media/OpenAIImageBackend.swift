import AinkradHostRuntime
import Foundation

/// OpenAI image-generation backend. Key lives in the Keychain via SecretStore,
/// never a document. Mirrors ProviderTranscriptionBackend's request shape.
struct OpenAIImageBackend: MediaBackend {
    static let secretID = "media.openai.apiKey"
    // `SecretStore` is a plain (non-Sendable) `AnyObject` protocol; conformers
    // used here (KeychainSecretStore, InMemorySecretStore) are safe to hand
    // across isolation boundaries.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var baseURL: String = "https://api.openai.com/v1"
    var model: String = "gpt-image-1"
    var size: String = "1024x1024"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    private struct Response: Decodable {
        struct Item: Decodable { let b64_json: String? }
        let data: [Item]
    }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Image generation is not configured.")
        }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + "/images/generations") else {
            throw ToolError.message("Invalid media base URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": model, "prompt": prompt, "n": 1, "size": size]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode).")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.data.first?.b64_json, !b64.isEmpty else {
            throw ToolError.message("image_generate response contained no image data.")
        }
        return GeneratedImage(mediaType: "image/png", base64: b64)
    }
}
