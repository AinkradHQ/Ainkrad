import AinkradHostRuntime
import Foundation

/// Keyless image-generation backend for a locally-run, Automatic1111-compatible
/// Stable Diffusion server (also ComfyUI via the A1111 API shim). No key, no
/// card — configuration is just the server base URL (e.g. `http://127.0.0.1:7860`),
/// persisted in `MediaSettingsDocument.localSDURL` (not a credential).
/// `isConfigured == false` when no URL is set.
struct LocalStableDiffusionBackend: MediaBackend {
    let baseURL: String
    let http: DataHTTPClient

    var isConfigured: Bool { !normalizedBase.isEmpty }

    private var normalizedBase: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private struct Response: Decodable { let images: [String] }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        let base = normalizedBase
        guard !base.isEmpty else { throw ToolError.message("Image generation is not configured.") }
        guard let url = URL(string: base + "/sdapi/v1/txt2img") else {
            throw ToolError.message("Local Stable Diffusion URL is invalid.")
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["prompt": prompt, "steps": 20, "batch_size": 1]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from the local server.")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        // A1111 returns bare base64 PNG (no `data:` prefix).
        guard let b64 = decoded.images.first, !b64.isEmpty else {
            throw ToolError.message("Local Stable Diffusion returned no image.")
        }
        let sniffed = Data(base64Encoded: b64).map(MediaMime.sniff) ?? "image/png"
        return GeneratedImage(mediaType: sniffed, base64: b64)
    }
}
