import Foundation

/// Expands a custom-command body template against a raw argument string.
/// Supported tokens (single left-to-right scan, no regex):
///   `$ARGUMENTS` — the full trimmed argument string.
///   `$1`…`$9`    — the Nth whitespace-split argument; a missing index → "".
///   `$$`         — a literal `$`.
/// Any other `$` sequence (`$foo`, a trailing `$`) is emitted verbatim, so
/// shell-style text in a prompt is never mangled.
enum CustomCommandTemplate {
    static func expand(_ body: String, arguments: String) -> String {
        let all = arguments.trimmingCharacters(in: .whitespaces)
        let positional = all.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var out = ""
        let chars = Array(body)
        var i = 0
        while i < chars.count {
            guard chars[i] == "$" else {
                out.append(chars[i])
                i += 1
                continue
            }
            let rest = chars[(i + 1)...]
            if rest.first == "$" {  // $$ -> literal $
                out.append("$")
                i += 2
                continue
            }
            if body[body.index(body.startIndex, offsetBy: i)...].hasPrefix("$ARGUMENTS") {
                out.append(all)
                i += "$ARGUMENTS".count
                continue
            }
            if let number = rest.first?.wholeNumberValue, number > 0 {
                let idx = number - 1
                if idx < positional.count { out.append(positional[idx]) }
                i += 2
                continue  // else -> empty
            }
            out.append("$")
            i += 1  // lone $ -> verbatim
        }
        return out
    }
}
