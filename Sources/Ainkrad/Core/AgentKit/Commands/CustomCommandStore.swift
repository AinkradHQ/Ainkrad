import Foundation

/// Loads, validates, and dedups the active custom-command set from disk. The
/// `.md` files are the source of truth; `reload()` is idempotent and cheap.
/// A file whose name is unsafe (`SkillValidator.isSafeName` fails) or collides
/// with a builtin (`BuiltinCommands.reservedNames`) is skipped — a custom
/// command can never shadow `/new`, `/model`, etc. On a name collision across
/// scopes, project wins over user (a repo can override a personal command).
@MainActor
final class CustomCommandStore {
    private let paths: CustomCommandPaths
    private let fm: FileManager
    private(set) var commands: [CustomCommand] = []

    init(paths: CustomCommandPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fm = fileManager
        reload()
    }

    func all() -> [CustomCommand] { commands }

    func reload() {
        var byName: [String: CustomCommand] = [:]
        for (url, scope) in paths.commandFiles(fileManager: fm) {
            let name = url.deletingPathExtension().lastPathComponent
            guard SkillValidator.isSafeName(name),
                !BuiltinCommands.reservedNames.contains(name)
            else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let cmd = CustomCommandParser.parse(text, name: name, scope: scope)
            // project (enumerated after user) overrides user on collision.
            if let existing = byName[name], existing.scope == .project, scope == .user { continue }
            byName[name] = cmd
        }
        commands = byName.values.sorted { $0.name < $1.name }
    }
}
