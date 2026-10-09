import Foundation

/// Theme files for tests: `glassy` has a dark AND a light variant (system
/// font), `paper` is a light scheme, and two files are broken.
enum ThemeFixtures {
    static let lightVariant: [String: String] = [
        "glassy-dark.theme": #"""
        {"schemaVersion": 1, "id": "glassy.dark", "name": "Glassy", "base": "neonBlue",
         "host": {"language": {"id": "glassy", "name": "Glassy", "appearance": "dark",
                               "defaultColorScheme": "nord", "fontFamily": "system"}}}
        """#,
        "glassy-light.theme": #"""
        {"schemaVersion": 1, "id": "glassy.light", "name": "Glassy", "base": "neonBlue",
         "host": {"language": {"id": "glassy", "name": "Glassy", "appearance": "light",
                               "defaultColorScheme": "paper", "fontFamily": "system"}}}
        """#,
        "paper.scheme": #"""
        {"schemaVersion": 1, "id": "paper", "name": "Paper", "appearance": "light",
         "palette": {"background": "#F4F4F0"}}
        """#,
        "odd-dark.theme": #"""
        {"schemaVersion": 1, "id": "odd.dark", "name": "Odd", "base": "neonBlue",
         "host": {"language": {"id": "odd", "name": "Odd", "appearance": "dark", "fontFamily": "comic"}}}
        """#,
    ]
    static let broken: [String: String] = [
        "broken.theme": "{ not json",
        "orphan.theme": #"{"schemaVersion": 1, "id": "orphan", "base": "nope"}"#,
    ]

    /// Loads, with one non-fatal AppKit warning (an unknown `material.kind`).
    static let warned: [String: String] = [
        "warned.theme": #"{"schemaVersion": 1, "id": "warned", "base": "neonBlue", "material": {"kind": "plasma"}}"#
    ]

    /// Writes `files` into `dir` (created if needed) and returns it.
    @discardableResult
    static func write(_ files: [String: String], to dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, body) in files {
            try? body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    static func tempDir(_ files: [String: String]) -> URL {
        write(files, to: FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString)"))
    }
}
