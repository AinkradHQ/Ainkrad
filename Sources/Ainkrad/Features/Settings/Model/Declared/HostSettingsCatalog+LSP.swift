import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// Tools → Language servers as DECLARED rows: one row per server (its health
/// in the help line; On, Off or Remove…), then one editor — pick a server or
/// "New server…" and edit its command, args and file globs.
@MainActor
extension HostSettingsCatalog {
    static func lspFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let registry = environment.lspServerRegistry
        let drafts = environment.settingsDrafts
        let servers = registry.servers()

        var fields: [SettingsField] = [
            SettingsField(
                path: group.appending("detect"), label: "Detect on PATH",
                help: "Adds any language server already installed on your PATH.",
                keywords: ["lsp", "detect", "autodetect", "path"],
                kind: .action(title: "Detect") {
                    Task.detached { [registry] in
                        let found = LSPServerRegistry.autodetect()
                        await MainActor.run { for config in found { registry.upsert(config) } }
                    }
                })
        ]
        fields += servers.map { config in
            SettingsField(
                path: group.appending("server-\(config.id)"), label: config.id,
                help: "\(lspHealth(registry, config.id)) · \(config.command)",
                keywords: ["lsp", "language server", config.id],
                kind: .select(
                    options: [
                        SettingsOption(id: "on", title: "On"),
                        SettingsOption(id: "off", title: "Off"),
                        SettingsOption(id: "remove", title: "Remove…"),
                    ],
                    selection: Binding(
                        get: { config.enabled ? "on" : "off" },
                        set: { choice in
                            if choice == "remove" {
                                if confirm(
                                    "Remove \(config.id)?",
                                    "This deletes this language server's configuration. This can't be undone.",
                                    action: "Remove")
                                {
                                    registry.remove(id: config.id)
                                    if drafts.lspSelection == config.id { selectLSP("", registry, drafts) }
                                }
                                return
                            }
                            registry.setEnabled(choice == "on", for: config.id)
                        })))
        }

        // The editor.
        let editing = registry.config(id: drafts.lspSelection)
        fields.append(
            SettingsField(
                path: group.appending("edit"), label: "Edit",
                help: editing == nil
                    ? "Add a language server by its command and file globs."
                    : "Change \(drafts.lspSelection)'s launch.",
                keywords: ["lsp", "edit", "add", "server"],
                kind: .select(
                    options: [SettingsOption(id: "", title: "New server…")]
                        + servers.map { SettingsOption(id: $0.id, title: $0.id) },
                    selection: Binding(
                        get: { drafts.lspSelection },
                        set: { selectLSP($0, registry, drafts) }))))
        if editing == nil {
            fields.append(
                SettingsField(
                    path: group.appending("edit-id"), label: "Language", help: "e.g. swift, python",
                    kind: .text(Binding(get: { drafts.lspID }, set: { drafts.lspID = $0 }))))
        }
        fields += [
            SettingsField(
                path: group.appending("edit-command"), label: "Command",
                help: "An absolute path, or a name on your PATH.",
                kind: .text(Binding(get: { drafts.lspCommand }, set: { drafts.lspCommand = $0 }))),
            SettingsField(
                path: group.appending("edit-args"), label: "Arguments", help: "Comma-separated, optional.",
                kind: .text(Binding(get: { drafts.lspArgs }, set: { drafts.lspArgs = $0 }))),
            SettingsField(
                path: group.appending("edit-globs"), label: "File globs", help: "Comma-separated, e.g. *.swift",
                kind: .text(Binding(get: { drafts.lspGlobs }, set: { drafts.lspGlobs = $0 }))),
        ]
        let id = (editing?.id ?? drafts.lspID).trimmingCharacters(in: .whitespacesAndNewlines)
        let problem: String? =
            id.isEmpty
            ? "Enter a language id."
            : (editing == nil && registry.config(id: id) != nil)
                ? "\(id) is already configured."
                : drafts.lspCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Enter a command."
                    : nil
        fields.append(
            SettingsField(
                path: group.appending("edit-save"), label: editing == nil ? "Add server" : "Save changes",
                help: problem ?? "Ready.",
                kind: .action(title: editing == nil ? "Add" : "Save") {
                    guard problem == nil else { return }
                    registry.upsert(
                        LSPServerConfig(
                            id: id, command: drafts.lspCommand.trimmingCharacters(in: .whitespacesAndNewlines),
                            args: splitList(drafts.lspArgs), fileGlobs: splitList(drafts.lspGlobs),
                            enabled: editing?.enabled ?? true))
                    selectLSP(id, registry, drafts)
                }))
        return fields
    }

    private static func selectLSP(_ id: String, _ registry: LSPServerRegistry, _ drafts: HostSettingsDrafts) {
        drafts.lspSelection = id
        let config = registry.config(id: id)
        drafts.lspID = ""
        drafts.lspCommand = config?.command ?? ""
        drafts.lspArgs = config?.args.joined(separator: ", ") ?? ""
        drafts.lspGlobs = config?.fileGlobs.joined(separator: ", ") ?? ""
    }

    private static func splitList(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func lspHealth(_ registry: LSPServerRegistry, _ id: String) -> String {
        guard let config = registry.config(id: id), config.enabled else { return "Off" }
        let sessions = registry.health.filter { $0.key.hasPrefix("\(id)::") }
        if sessions.values.contains(where: { $0 == .connected }) { return "Connected" }
        if sessions.values.contains(where: {
            if case .failed = $0 { return true }
            return false
        }) {
            return "Failed"
        }
        return "Not connected yet"
    }
}
