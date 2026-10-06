import AinkradHostRuntime
import Foundation

/// Stability AI (Stable Diffusion) image backend. Key in the Keychain via
/// SecretStore, never a document. Uses the v1 SDXL text-to-image endpoint,
/// which returns base64 JSON artifacts.
struct StabilityImageBackend: MediaBackend {
    static let secretID = "media.stability.apiKey"
    // `nonisolated(unsafe)`: an immutable `let`; `KeychainSecretStore` keeps no mutable state and Keychain calls are thread-safe.
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var engine: String = "stable-diffusion-xl-1024-v1-0"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    private struct Response: Decodable {
        struct Artifact: Decodable { let base64: String? }
        let artifacts: [Artifact]
    }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Image generation is not configured.")
        }
        guard let url = URL(string: "https://api.stability.ai/v1/generation/\(engine)/text-to-image") else {
            throw ToolError.message("Invalid Stability URL.")
        }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["text_prompts": [["text": prompt]], "samples": 1]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from Stability.")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.artifacts.first?.base64, !b64.isEmpty else {
            throw ToolError.message("Stability response contained no image data.")
        }
        return GeneratedImage(mediaType: "image/png", base64: b64)
    }
}
