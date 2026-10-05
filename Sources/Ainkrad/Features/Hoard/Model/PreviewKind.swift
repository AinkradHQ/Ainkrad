import Foundation

/// How a file should be previewed.
///
/// Source files deliberately do NOT go to Quick Look: it renders them as flat
/// monospaced text with no highlighting, which is strictly worse than the code
/// block the kit already ships. Everything Quick Look genuinely does better —
/// PDFs, video, office documents — falls through to it.
enum PreviewKind: Equatable, Sendable {
    case code(language: String)
    case text
    case image
    case quickLook
    case directory
    /// Nothing useful to show — an empty pane beats a broken one.
    case none
}

/// Extensions the kit's highlighter understands, mapped to its language name.
private let codeLanguages: [String: String] = [
    "swift": "swift",
    "js": "javascript", "mjs": "javascript", "jsx": "javascript",
    "ts": "typescript", "tsx": "typescript",
    "py": "python", "rb": "ruby", "go": "go", "rs": "rust",
    "c": "c", "h": "c", "cpp": "cpp", "hpp": "cpp", "cc": "cpp",
    "java": "java", "kt": "kotlin", "cs": "csharp", "php": "php",
    "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash",
    "json": "json", "yml": "yaml", "yaml": "yaml", "toml": "toml",
    "xml": "xml", "html": "html", "css": "css", "scss": "scss",
    "sql": "sql", "swiftinterface": "swift",
]

/// Extensions that are plain text — shown as text, not highlighted as code.
private let textExtensions: Set<String> = [
    "txt", "md", "markdown", "rst", "log", "csv", "tsv", "env",
    "gitignore", "gitattributes", "editorconfig", "plist", "strings",
]

private let imageExtensions: Set<String> = [
    "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg", "ico",
]

/// Files Quick Look handles well and we have no better renderer for.
private let quickLookExtensions: Set<String> = [
    "pdf", "mov", "mp4", "m4v", "avi", "mkv", "mp3", "wav", "aac", "flac",
    "m4a", "key", "pages", "numbers", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
]

func previewKind(for entry: FileEntry) -> PreviewKind {
    if entry.isDirectory { return .directory }

    let ext = entry.fileExtension
    // Extensionless dotfiles are named, not typed: ".gitignore" is text even
    // though `pathExtension` gives "gitignore" for it and "" for ".env".
    if ext.isEmpty {
        let bare = entry.name.hasPrefix(".") ? String(entry.name.dropFirst()) : entry.name
        return textExtensions.contains(bare.lowercased()) ? .text : .none
    }

    if let language = codeLanguages[ext] { return .code(language: language) }
    if textExtensions.contains(ext) { return .text }
    if imageExtensions.contains(ext) { return .image }
    if quickLookExtensions.contains(ext) { return .quickLook }
    return .none
}

/// Cap for text and code previews. Rendering a 200 MB log into a `Text` view
/// would hang the pane; a truncated head is honest and instant.
let previewByteLimit = 256 * 1024

/// Reads at most `previewByteLimit` bytes as UTF-8, or `nil` if it isn't text
/// after all — a `.swift` file containing binary should fall back, not render
/// as replacement characters.
func previewText(at url: URL, limit: Int = previewByteLimit) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: limit), !data.isEmpty else { return nil }
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    return text
}
