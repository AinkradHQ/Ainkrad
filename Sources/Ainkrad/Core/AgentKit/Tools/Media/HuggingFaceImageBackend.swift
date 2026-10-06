import AinkradHostRuntime
import Foundation

/// Hugging Face Inference API image backend. Token in the Keychain via
/// SecretStore, never a document. Free-tier accounts issue a token with no
/// payment card. The inference endpoint returns raw image bytes (MIME sniffed).
struct HuggingFaceImageBackend: MediaBackend {
    static let secretID = "media.huggingface.apiKey"
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var model: String = "black-forest-labs/FLUX.1-schnell"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Image generation is not configured.")
        }
        guard let url = URL(string: "https://api-inference.huggingface.co/models/\(model)") else {
            throw ToolError.message("Invalid Hugging Face URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["inputs": prompt])
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from Hugging Face.")
        }
        guard !data.isEmpty else { throw ToolError.message("Hugging Face returned no image data.") }
        return GeneratedImage(mediaType: MediaMime.sniff(data), base64: data.base64EncodedString())
    }
}
