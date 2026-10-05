import Foundation

extension CustomCommandStore {
    /// Builds one `SlashCommand` per loaded command, registrable into
    /// `CommandRegistry` (mirrors `SkillCommandStore.slashCommands(registry:)`).
    /// The handler expands the body template against the raw arg string and
    /// sends it as a normal prompt — a custom command never bypasses the
    /// permission gate, exactly like a skill command. Builtin/collision safety
    /// is already enforced in `reload()`; this is a pure projection.
    @MainActor
    func slashCommands() -> [SlashCommand] {
        all().map { command in
            let summary = command.description.isEmpty ? "Custom command" : command.description
            let usage =
                command.argumentHint.isEmpty
                ? "/\(command.name)"
                : "/\(command.name) \(command.argumentHint)"
            return SlashCommand(
                name: command.name, summary: summary,
                usage: usage, category: .custom
            ) { args, session in
                session.send(CustomCommandTemplate.expand(command.body, arguments: args))
                return .handled(note: nil)
            }
        }
    }
}
