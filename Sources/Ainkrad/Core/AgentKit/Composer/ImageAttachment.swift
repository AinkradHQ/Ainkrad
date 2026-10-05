import Foundation

/// A user-attached image, loaded from disk and validated before it becomes an
/// `AgentContentBlock.image`. Media type is sniffed from the file's magic
/// bytes (not the extension) so a mis-named file is still rejected/accepted
/// correctly.
struct ImageAttachment: Equatable, Sendable {
    let mediaType: String
    let base64: String

    /// Providers cap image inputs well below this; 5 MB keeps the composer
    /// responsive and avoids surprising multi-MB base64 payloads on the wire.
    static let maxBytes = 5 * 1024 * 1024

    enum LoadError: Error, Equatable {
        case unsupportedFormat
        case tooLarge(bytes: Int)
    }

    static func from(fileURL: URL) throws -> ImageAttachment {
        let data = try Data(contentsOf: fileURL)
        guard data.count <= maxBytes else {
            throw LoadError.tooLarge(bytes: data.count)
        }
        guard let mediaType = sniffMediaType(data) else {
            throw LoadError.unsupportedFormat
        }
        return ImageAttachment(mediaType: mediaType, base64: data.base64EncodedString())
    }

    /// Sniffs PNG/JPEG/GIF/WEBP from magic bytes. Returns nil for anything else.
    static func sniffMediaType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return nil }

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "image/png"
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return "image/gif"
        }
        if bytes.count >= 12,
            bytes[0...3] == [0x52, 0x49, 0x46, 0x46],  // "RIFF"
            bytes[8...11] == [0x57, 0x45, 0x42, 0x50]
        {  // "WEBP"
            return "image/webp"
        }
        return nil
    }
}

/// Warns when an image is attached but the resolved model lacks `.vision`.
/// The composer surfaces this before send rather than letting the provider
/// reject the request (or silently drop the image).
@MainActor
func visionGate(model: String, catalog: ModelCatalog, hasImage: Bool) -> String? {
    guard hasImage else { return nil }
    guard let descriptor = catalog.descriptor(for: model), descriptor.capabilities.contains(.vision) else {
        return "\(model) doesn't support image input — remove the attachment or switch models."
    }
    return nil
}
