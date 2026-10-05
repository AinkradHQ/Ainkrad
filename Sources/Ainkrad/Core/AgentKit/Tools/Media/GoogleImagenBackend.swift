import AinkradHostRuntime
import Foundation

/// Google Imagen (via the Generative Language API) image backend. Key in the
/// Keychain via SecretStore, never a document. The key is passed as the `key`
/// query parameter per the Generative Language API convention.
struct GoogleImagenBackend: MediaBackend {
    static let secretID = "media.google.apiKey"
    nonisolated(unsafe) let secrets: SecretStore
    let http: DataHTTPClient
    var model: String = "imagen-3.0-generate-002"

    var isConfigured: Bool { !(secrets.secret(for: Self.secretID) ?? "").isEmpty }

    private struct Response: Decodable {
        struct Prediction: Decodable { let bytesBase64Encoded: String? }
        let predictions: [Prediction]
    }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        guard let key = secrets.secret(for: Self.secretID), !key.isEmpty else {
            throw ToolError.message("Image generation is not configured.")
        }
        guard
            var comps = URLComponents(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):predict")
        else {
            throw ToolError.message("Invalid Google Imagen URL.")
        }
        comps.queryItems = [.init(name: "key", value: key)]
        guard let url = comps.url else { throw ToolError.message("Invalid Google Imagen URL.") }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "instances": [["prompt": prompt]],
            "parameters": ["sampleCount": 1],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from Google Imagen.")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.predictions.first?.bytesBase64Encoded, !b64.isEmpty else {
            throw ToolError.message("Google Imagen response contained no image data.")
        }
        let sniffed = Data(base64Encoded: b64).map(MediaMime.sniff) ?? "image/png"
        return GeneratedImage(mediaType: sniffed, base64: b64)
    }
}
