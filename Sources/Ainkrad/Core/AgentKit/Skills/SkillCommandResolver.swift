import Foundation

enum SkillCommandResolution: Equatable {
    case prompt(String)  // composed text to run
    case brokenBinding(command: String, missingSkill: String)
    case notASkillCommand
}

/// Turns `/name [args]` into the prompt that runs the bound skill. A command
/// bound to a since-deleted/uninstalled skill yields `.brokenBinding` (the
/// manager surfaces this as a disabled/broken binding — never a crash, never a
/// silent no-op); an unbound slash or plain text is `.notASkillCommand` so
/// built-in commands and normal prompts flow past unchanged.
@MainActor
enum SkillCommandResolver {
    static func resolve(_ input: String, store: SkillCommandStore, registry: SkillRegistry) -> SkillCommandResolution {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return .notASkillCommand }
        let parts = trimmed.dropFirst().split(separator: " ", maxSplits: 1)
        guard let name = parts.first.map(String.init),
            let skillName = store.skillName(forCommand: name)
        else { return .notASkillCommand }
        let args = parts.count > 1 ? String(parts[1]) : ""
        guard let skill = registry.skill(named: skillName) else {
            return .brokenBinding(command: name, missingSkill: skillName)
        }
        let composed =
            args.isEmpty
            ? skill.body
            : "\(skill.body)\n\nArguments: \(args)"
        return .prompt(composed)
    }
}

extension SkillCommandStore {
    /// Builds one `SlashCommand` per current binding, registrable into
    /// `CommandRegistry` (`CommandRegistry.register(_:)`) so `/name` dispatches
    /// through the existing command path and its handler runs through the
    /// normal session/tool/permission flow — a skill command never bypasses
    /// the permission gate. Bindings that would collide with a builtin name
    /// are excluded (defense in depth: `bind(command:toSkill:)` already
    /// refuses to persist those).
    @MainActor
    func slashCommands(registry: SkillRegistry) -> [SlashCommand] {
        all()
            .filter { !BuiltinCommands.reservedNames.contains($0.command) }
            .map { binding in
                SlashCommand(
                    name: binding.command,
                    summary: "Run skill \(binding.skillName)",
                    usage: "/\(binding.command) [args]",
                    category: .skill
                ) { [weak self] args, session in
                    guard let self else { return .notACommand }
                    switch SkillCommandResolver.resolve("/\(binding.command) \(args)", store: self, registry: registry)
                    {
                    case .prompt(let composed):
                        session.send(composed)
                        return .handled(note: nil)
                    case .brokenBinding(_, let missingSkill):
                        return .handled(note: "Bound skill \"\(missingSkill)\" is missing.")
                    case .notASkillCommand:
                        return .notACommand
                    }
                }
            }
    }
}
