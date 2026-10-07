import Foundation

/// Translates a shell-style glob to an anchored NSRegularExpression. `**`
/// crosses path separators; `*`/`?` do not. Kept separate from GlobTool so
/// the matching semantics are unit-testable in isolation.
///
/// `GlobMatcher` itself is declared in `Autonomy/FileChangeWatcher.swift`
/// (a simpler `fnmatch`-based `matches(_:glob:)` used for FSEvents
/// filtering). This extension adds the richer pattern-based matcher used by
/// the code-search tools without redeclaring the type.
extension GlobMatcher {
    static func matches(_ relativePath: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^\(translate(pattern))$") else { return false }
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return regex.firstMatch(in: relativePath, range: range) != nil
    }

    private static func translate(_ pattern: String) -> String {
        var out = ""
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    out += ".*"
                    i += 2
                    if i < chars.count && chars[i] == "/" { i += 1 }  // "**/" also matches zero dirs
                    continue
                }
                out += "[^/]*"
            case "?": out += "[^/]"
            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "[", "]", "\\":
                out += "\\\(c)"
            default: out.append(c)
            }
            i += 1
        }
        return out
    }
}
