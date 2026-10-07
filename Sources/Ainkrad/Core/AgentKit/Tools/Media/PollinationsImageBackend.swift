import AinkradHostRuntime
import Foundation

/// Keyless image-generation backend backed by Pollinations.ai. No API key, no
/// account, no payment card — always `isConfigured`. Requests a single image by
/// GET and returns the raw bytes (MIME sniffed). The direct analog of the
/// DuckDuckGo web-search backend: zero setup, at the cost of no quality/rate
/// guarantees.
struct PollinationsImageBackend: MediaBackend {
    let http: DataHTTPClient
    var baseURL: String = "https://image.pollinations.ai"

    /// No credential to configure — the whole point of this backend.
    var isConfigured: Bool { true }

    func generateImage(prompt: String) async throws -> GeneratedImage {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        // Encode the prompt as a single path segment.
        let encoded =
            prompt.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? prompt.replacingOccurrences(of: " ", with: "%20")
        guard var comps = URLComponents(string: "\(base)/prompt/\(encoded)") else {
            throw ToolError.message("Invalid Pollinations URL.")
        }
        comps.queryItems = [.init(name: "nologo", value: "true")]
        guard let url = comps.url else { throw ToolError.message("Invalid Pollinations URL.") }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ToolError.message("image_generate got HTTP \(response.statusCode) from Pollinations.")
        }
        guard !data.isEmpty else { throw ToolError.message("Pollinations returned no image data.") }
        return GeneratedImage(mediaType: MediaMime.sniff(data), base64: data.base64EncodedString())
    }
}
