import Foundation

/// A generated image: a sniffed MIME type + raw bytes base64-encoded, matching
/// `AgentContentBlock.image(mediaType:base64:)`'s convention.
struct GeneratedImage: Equatable, Sendable {
    let mediaType: String
    let base64: String
}

/// Pluggable image-generation provider. `isConfigured == false` drives the
/// graceful "not configured" path in `ImageGenerateTool` (never an error).
protocol MediaBackend: Sendable {
    var isConfigured: Bool { get }
    func generateImage(prompt: String) async throws -> GeneratedImage
}

/// Sniffs an image MIME type from leading magic bytes, for backends that return
/// raw image bytes (Pollinations, Hugging Face) rather than a declared type.
/// Defaults to `image/png` — the type the Live Scry + `AgentContentBlock`
/// already assume — when the signature is unrecognized.
/// Derives a file extension from a URL path, for backends that return a link to
/// a generated asset (Replicate/Luma/Runway/fal videos). Pure and unit-tested.
enum MediaFileExtension {
    static func forURL(_ urlString: String, default fallback: String) -> String {
        guard let url = URL(string: urlString) else { return fallback }
        let ext = url.pathExtension.lowercased()
        let known: Set<String> = ["mp4", "webm", "mov", "gif", "png", "jpg", "jpeg"]
        return known.contains(ext) ? ext : fallback
    }
}

enum MediaMime {
    static func sniff(_ data: Data) -> String {
        let b = [UInt8](data.prefix(12))
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "image/jpeg" }
        if b.count >= 4, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "image/png" }
        if b.count >= 3, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "image/gif" }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
            b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50
        {
            return "image/webp"
        }
        return "image/png"
    }
}
