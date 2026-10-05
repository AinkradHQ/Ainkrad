import AinkradHostRuntime
import Foundation

/// One `/name` → skill binding. `command` is the bare name typed after `/`
/// (never includes the slash itself); `skillName` is the bound `Skill.name`.
struct SkillCommandBinding: Codable, Equatable, Identifiable {
    var id: String { command }
    let command: String
    let skillName: String
}

struct SkillCommandsDocument: PersistableDocument {
    static let documentID = "skill-commands"
    var bindings: [SkillCommandBinding]

    init(bindings: [SkillCommandBinding] = []) { self.bindings = bindings }

    // Host idiom: forward-compatible decoding (decodeIfPresent + defaults) so a
    // payload missing newer keys never throws. See AuthProfilesDocument / RouterOutcomeDocument.
    enum CodingKeys: String, CodingKey { case bindings }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindings = try c.decodeIfPresent([SkillCommandBinding].self, forKey: .bindings) ?? []
    }
}

/// CRUD over the command-name → skill-name bindings that back custom `/name`
/// skill commands. Persisted (`SkillCommandsDocument`) so bindings survive
/// relaunch; `SkillCommandResolver` reads through this store, and the app's
/// command wiring registers one `SlashCommand` per binding into `CommandRegistry`
/// (see `SkillCommandStore.slashCommands(registry:)`).
@MainActor
final class SkillCommandStore {
    private var doc: SkillCommandsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.doc = persistence.load(SkillCommandsDocument.self) ?? SkillCommandsDocument()
    }

    func all() -> [SkillCommandBinding] { doc.bindings }

    /// Binds `command` to `skillName`, replacing any existing binding for that
    /// name. A no-op (nothing persisted) when `command` fails
    /// `isValidCommandName` — in particular when it collides with a builtin
    /// (`/new`, `/model`, …), which a skill command must never be able to
    /// shadow or override.
    func bind(command: String, toSkill skillName: String) {
        guard SkillCommandStore.isValidCommandName(command) else { return }
        doc.bindings.removeAll { $0.command == command }
        doc.bindings.append(SkillCommandBinding(command: command, skillName: skillName))
        persistence.save(doc)
    }

    func unbind(command: String) {
        doc.bindings.removeAll { $0.command == command }
        persistence.save(doc)
    }

    func skillName(forCommand command: String) -> String? {
        doc.bindings.first { $0.command == command }?.skillName
    }

    /// A bindable command name: a safe slug (reuses `SkillValidator`'s
    /// lowercase-slug allow-list so a name can never contain `/`, whitespace,
    /// or control characters) that is also not one of `CommandRegistry`'s
    /// builtin names — a skill command can never hijack `/new`, `/model`, etc.
    static func isValidCommandName(_ name: String) -> Bool {
        SkillValidator.isSafeName(name) && !BuiltinCommands.reservedNames.contains(name)
    }
}
