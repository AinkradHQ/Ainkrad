import Foundation

/// How a committed `@file` mention is carried into the outgoing turn.
/// `.embed` inlines the file's content in a `<mentioned_files>` block;
/// `.reference` leaves only the `@path` token in the draft.
enum MentionMode: String, Sendable, CaseIterable {
    case embed
    case reference
}

/// A file the user @-mentioned in the composer, tracked as structured
/// composer state alongside `pendingImages` (see `SageComposerBar`).
struct ComposerMention: Equatable, Sendable {
    let path: String
    var mode: MentionMode

    init(path: String, mode: MentionMode = .embed) {
        self.path = path
        self.mode = mode
    }
}

/// Reads a mentioned file for embedding, applying the SAME guards as
/// `ReadFileTool`: absolute-path regular file, `<= ReadFileTool.maxBytes`,
/// valid UTF-8. Returns `nil` on any failure so the caller falls back to a
/// path-only reference (never throws into the send path).
@MainActor
enum MentionFileReader {
    static func read(path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return nil }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
            size > ReadFileTool.maxBytes
        {
            return nil
        }
        guard let data = try? Data(contentsOf: url), data.count <= ReadFileTool.maxBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
