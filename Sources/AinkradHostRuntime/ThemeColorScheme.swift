import Foundation

/// A parsed `.scheme` file: the colours that sit on top of a design language
/// (`palette`, `terminal`, `syntax` and the sky/icon `host` keys). Language
/// keys (shape, material, motion, …) are not allowed in a scheme.
/// Named `ThemeColorScheme` so it never collides with SwiftUI's `ColorScheme`.
public struct ThemeColorScheme: Sendable {
    public let id: String
    public let name: String
    public let appearance: ThemeAppearance
    /// The file's top-level JSON object, kept as data so composition can
    /// rebuild it without a second disk read.
    let raw: Data

    static let allowedKeys: Set<String> = [
        "schemaVersion", "id", "name", "appearance", "palette", "terminal", "syntax", "host",
    ]

    /// Parses a scheme's top-level object, returning a reason on failure.
    static func parse(_ dict: [String: Any]) -> Result<ThemeColorScheme, ThemeCatalogIssue> {
        guard let id = dict["id"] as? String, !id.isEmpty else {
            return .failure(ThemeCatalogIssue(subject: "scheme", message: "missing id"))
        }
        let subject = "scheme \(id)"
        for key in dict.keys.sorted() where !allowedKeys.contains(key) {
            return .failure(ThemeCatalogIssue(subject: subject, message: "key \(key) is not allowed in a colour scheme"))
        }
        guard let appearanceString = dict["appearance"] as? String,
            let appearance = ThemeAppearance(rawValue: appearanceString)
        else {
            return .failure(ThemeCatalogIssue(subject: subject, message: "appearance must be dark or light"))
        }
        guard let raw = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return .failure(ThemeCatalogIssue(subject: subject, message: "not serialisable"))
        }
        return .success(
            ThemeColorScheme(id: id, name: dict["name"] as? String ?? id, appearance: appearance, raw: raw))
    }
}

/// A problem found while loading theme or colour-scheme files. Loading never
/// traps: the offending file is skipped and the issue is kept for Settings.
struct ThemeCatalogIssue: Equatable, Sendable, CustomStringConvertible {
    let subject: String
    let message: String
    /// The file still loaded (AppKit's `unknownValue`); listed, not counted as a failure.
    var isWarning = false

    var description: String { "\(subject): \(isWarning ? "warning: " : "")\(message)" }
}
