import AppKit
import Foundation

/// Decodes a `data:` image URL (as produced by `image_generate`) into bytes /
/// an `NSImage`. `AsyncImage`/`URLSession` do not load the `data:` scheme, so
/// the canvas decodes these directly. The byte parse is pure and unit-tested.
enum ScryImageDecoding {
    /// Extracts the raw bytes from a base64 `data:` URL, e.g.
    /// `data:image/jpeg;base64,<...>`. Returns `nil` for non-data URLs or a
    /// malformed/empty payload.
    static func base64Payload(_ body: String) -> Data? {
        guard body.hasPrefix("data:"), let commaIndex = body.firstIndex(of: ",") else { return nil }
        let header = body[body.index(body.startIndex, offsetBy: 5)..<commaIndex]
        guard header.contains("base64") else { return nil }
        let b64 = String(body[body.index(after: commaIndex)...])
        guard !b64.isEmpty, let data = Data(base64Encoded: b64), !data.isEmpty else { return nil }
        return data
    }

    static func dataURLImage(_ body: String) -> NSImage? {
        base64Payload(body).flatMap { NSImage(data: $0) }
    }
}
