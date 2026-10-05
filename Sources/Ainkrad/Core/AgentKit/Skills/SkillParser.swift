import Foundation

enum SkillParseError: Error, Equatable {
    case missingFrontMatter
    case missingName
    case missingDescription
}

/// Minimal, dependency-free parser for the `SKILL.md` front-matter shape used by
/// agentskills.io / Agent Skills. Handles `key: value`, inline `[a, b]`, and
/// dashed multi-line lists — enough for `name`/`description`/`allowed-tools`/
/// `triggers`. NOT a general YAML parser (deliberately no SPM dependency).
///
/// This parser handles untrusted input (skills may come from a catalog): every
/// malformed shape below is a captured `SkillParseError`, never a crash.
enum SkillParser {
    /// Keys whose values are lists; every other key is a single scalar (so a
    /// `description` may contain commas without being split).
    private static let listKeys: Set<String> = ["allowed-tools", "triggers"]

    static func parse(_ text: String, source: SkillSource) throws -> Skill {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { throw SkillParseError.missingFrontMatter }
        let afterOpen = normalized.dropFirst("---\n".count)
        guard let close = afterOpen.range(of: "\n---") else { throw SkillParseError.missingFrontMatter }

        let yaml = String(afterOpen[afterOpen.startIndex..<close.lowerBound])
        var body = String(afterOpen[close.upperBound...])
        if body.hasPrefix("\n") { body.removeFirst() }

        let fields = parseFrontMatter(yaml)
        guard let name = fields["name"]?.first, !name.isEmpty else { throw SkillParseError.missingName }
        guard let description = fields["description"]?.first, !description.isEmpty else {
            throw SkillParseError.missingDescription
        }
        return Skill(
            name: name,
            description: description,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedTools: fields["allowed-tools"] ?? [],
            triggers: fields["triggers"] ?? [],
            source: source)
    }

    /// Returns each key mapped to its value(s). Scalars become a one-element
    /// array; list keys are split on commas / brackets / dashed lines.
    static func parseFrontMatter(_ yaml: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var currentListKey: String?

        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // A dashed item continues the most recent list-valued key.
            if trimmed.hasPrefix("- "), let key = currentListKey {
                let item = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                if !item.isEmpty { result[key, default: []].append(item) }
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }

            if listKeys.contains(key) {
                currentListKey = key
                if value.isEmpty {
                    result[key] = result[key] ?? []
                }  // dashed list follows
                else {
                    result[key] = splitList(value)
                }
            } else {
                currentListKey = nil
                result[key] = [unquote(value)]
            }
        }
        return result
    }

    private static func splitList(_ value: String) -> [String] {
        var v = value
        if v.hasPrefix("["), v.hasSuffix("]") { v = String(v.dropFirst().dropLast()) }
        return v.split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
