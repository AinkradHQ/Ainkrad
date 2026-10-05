import Foundation

/// A file-based custom slash command. `name` is derived from the filename
/// (never read from the file); `body` is a prompt template expanded at dispatch
/// time (see `CustomCommandTemplate`). Front-matter is OPTIONAL — a bare
/// markdown body with no `---` fence is a valid command.
struct CustomCommand: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let argumentHint: String
    let body: String
    let scope: Scope
    enum Scope: String, Equatable { case user, project }
}

/// Minimal, dependency-free parser for a custom-command `.md` file. Front-matter
/// is optional; a file that does not open with a closed `---` fence is treated
/// as an all-body command. Reuses `SkillParser.parseFrontMatter` so the two
/// front-matter dialects never drift. Never throws — a hand-edited/malformed
/// file degrades to "whole text is the body", matching the Skills subsystem's
/// degrade-don't-crash posture.
enum CustomCommandParser {
    static func parse(_ text: String, name: String, scope: CustomCommand.Scope) -> CustomCommand {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return CustomCommand(
                name: name, description: "", argumentHint: "",
                body: normalized, scope: scope)
        }
        let afterOpen = normalized.dropFirst("---\n".count)
        guard let close = afterOpen.range(of: "\n---") else {
            // Unclosed fence → treat the whole original text as the body.
            return CustomCommand(
                name: name, description: "", argumentHint: "",
                body: normalized, scope: scope)
        }
        let yaml = String(afterOpen[afterOpen.startIndex..<close.lowerBound])
        var body = String(afterOpen[close.upperBound...])
        if body.hasPrefix("\n") { body.removeFirst() }
        let fields = SkillParser.parseFrontMatter(yaml)
        return CustomCommand(
            name: name,
            description: fields["description"]?.first ?? "",
            argumentHint: fields["argument-hint"]?.first ?? "",
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            scope: scope)
    }
}
