import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import AppKit
import SwiftUI

/// Skills as DECLARED rows, over `SkillsManagerViewModel`. A skill's source is
/// edited in the SKILL.md file itself (Open SKILL.md…), not in a text area
/// inside Settings — a whole document is not a setting.
@MainActor
extension HostSettingsCatalog {
    static func skillGroups(_ environment: AppEnvironment, page: SettingsPath) -> [SettingsGroup] {
        let drafts = environment.settingsDrafts
        let model = drafts.skills(environment)
        let registry = model.registry

        // Active.
        let active = page.appending("manager")
        var activeFields = [
            SettingsField(
                path: active.appending("reload"), label: "Reload skills",
                help: "Re-read skills from disk — after editing a SKILL.md outside Ainkrad.",
                keywords: ["skill", "reload", "refresh"],
                kind: .action(title: "Reload") {
                    registry.reload()
                    environment.resyncSkillCommands()
                })
        ]
        activeFields += registry.skills.map { skill in
            var options = [SettingsOption(id: "keep", title: "Active")]
            if skill.source == .local { options.append(SettingsOption(id: "open", title: "Open SKILL.md…")) }
            options.append(SettingsOption(id: "delete", title: "Delete…"))
            let details = [
                skill.source.rawValue.capitalized,
                skill.triggers.isEmpty ? nil : "triggers: \(skill.triggers.joined(separator: ", "))",
                skill.allowedTools.isEmpty ? nil : "tools: \(skill.allowedTools.joined(separator: ", "))",
            ]
            .compactMap { $0 }.joined(separator: " · ")
            return SettingsField(
                path: active.appending("skill-\(skill.name)"), label: skill.name,
                help: skill.description.isEmpty ? details : "\(skill.description) — \(details)",
                keywords: ["skill", skill.name.lowercased()] + skill.triggers.map { $0.lowercased() },
                kind: .select(
                    options: options,
                    selection: Binding(
                        get: { "keep" },
                        set: { choice in
                            switch choice {
                            case "open": NSWorkspace.shared.open(registry.paths.skillFile(skill.name))
                            case "delete":
                                confirm(
                                    environment.settingsDrafts,
                                    "Delete \(skill.name)?", "This removes the skill's folder from disk.",
                                    action: "Delete"
                                ) {
                                    model.delete(skill)
                                }
                            default: break
                            }
                        })))
        }
        var groups = [
            SettingsGroup(
                path: active, title: "Skills",
                footerNote: registry.skills.isEmpty
                    ? "No active skills. Approve a proposal, or install one from the App Store."
                    : "Installed skills. Local ones are edited in their SKILL.md.",
                fields: activeFields)
        ]

        // Proposed — only while something is pending; the page's badge counts them.
        let proposed = page.appending("proposed")
        let proposals = registry.proposals()
        if !proposals.isEmpty {
            groups.append(
                SettingsGroup(
                    path: proposed, title: "Proposed",
                    footerNote: "Drafts the assistant proposed via propose_skill, for review before they go active.",
                    fields: proposals.map { proposal in
                        let issues = proposal.issues.map { issue -> String in
                            switch issue {
                            case .unsafeName(let name): "unsafe name \"\(name)\""
                            case .emptyBody: "empty body"
                            case .emptyDescription: "empty description"
                            }
                        }
                        var options = [SettingsOption(id: "pending", title: "Pending")]
                        if proposal.skill != nil { options.append(SettingsOption(id: "approve", title: "Approve")) }
                        options.append(SettingsOption(id: "discard", title: "Discard…"))
                        return SettingsField(
                            path: proposed.appending("proposal-\(proposal.name)"), label: proposal.name,
                            help: ([proposal.skill?.description ?? proposal.error ?? "Unreadable draft"] + issues)
                                .joined(separator: " · "),
                            keywords: ["proposal", "skill", proposal.name.lowercased()],
                            kind: .select(
                                options: options,
                                selection: Binding(
                                    get: { "pending" },
                                    set: { choice in
                                        if choice == "approve" { model.approve(proposal) }
                                        if choice == "discard" {
                                            confirm(
                                                environment.settingsDrafts,
                                                "Discard \(proposal.name)?",
                                                "The proposed draft is deleted.", action: "Discard"
                                            ) {
                                                model.discard(proposal)
                                            }
                                        }
                                    })))
                    }))
        }

        // Commands.
        let commands = page.appending("commands")
        let names = registry.skills.map(\.name)
        if drafts.newCommandSkill.isEmpty || !names.contains(drafts.newCommandSkill) {
            drafts.newCommandSkill = names.first ?? ""
        }
        var commandFields: [SettingsField] = model.store.all().map { binding in
            let broken = registry.skill(named: binding.skillName) == nil
            return SettingsField(
                path: commands.appending("command-\(binding.command)"), label: "/\(binding.command)",
                help: broken ? "Bound skill \"\(binding.skillName)\" is missing" : "Runs \(binding.skillName)",
                keywords: ["command", "slash", binding.command],
                kind: .action(title: "Unbind") { model.unbind(binding.command) })
        }
        if names.isEmpty {
            commandFields.append(
                SettingsField(
                    path: commands.appending("none"), label: "Bind a command",
                    help: "Approve at least one skill to bind it to a command.",
                    kind: .shortcut(.constant("—"))))
        } else {
            commandFields += [
                SettingsField(
                    path: commands.appending("new-name"), label: "Command",
                    help: "A lowercase slug, typed after /.",
                    keywords: ["command", "slash", "bind"],
                    kind: .text(Binding(get: { drafts.newCommand }, set: { drafts.newCommand = $0 }))),
                SettingsField(
                    path: commands.appending("new-skill"), label: "Runs skill",
                    kind: .select(
                        options: names.map { SettingsOption(id: $0, title: $0) },
                        selection: Binding(
                            get: { drafts.newCommandSkill },
                            set: { drafts.newCommandSkill = $0 }))),
                SettingsField(
                    path: commands.appending("new-bind"), label: "Bind command",
                    help: model.bindError ?? "Adds /\(drafts.newCommand.isEmpty ? "name" : drafts.newCommand).",
                    kind: .action(title: "Bind") {
                        if model.bind(command: drafts.newCommand, toSkill: drafts.newCommandSkill) {
                            drafts.newCommand = ""
                        }
                    }),
            ]
        }
        groups.append(
            SettingsGroup(
                path: commands, title: "Commands",
                footerNote: "Bind a skill to a /name slash command.", fields: commandFields))

        // Load errors, only when there are any.
        if !registry.loadErrors.isEmpty {
            let errors = page.appending("errors")
            groups.append(
                SettingsGroup(
                    path: errors, title: "Load errors",
                    footerNote: "Skills that failed to load from a malformed SKILL.md.",
                    fields: registry.loadErrors.map { err in
                        SettingsField(
                            path: errors.appending(err.name), label: err.name, help: err.message,
                            kind: .action(title: "Open") {
                                NSWorkspace.shared.open(registry.paths.skillFile(err.name))
                            })
                    }))
        }
        return groups
    }
}
