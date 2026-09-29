import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// A new MCP server as typed in the declared editor.
struct MCPServerDraft: Equatable {
    var transport: MCPTransportKind = .stdio
    var id = "", name = "", command = "", args = "", envKeys = "", url = "", headerKeys = ""
}

/// Grouping and wording the MCP settings share with their tests.
enum MCPServerGrouping {
    nonisolated static func appConfigs(from configs: [MCPServerConfig]) -> [MCPServerConfig] {
        configs.filter { $0.transport == .inProcess }
    }
    nonisolated static func externalConfigs(from configs: [MCPServerConfig]) -> [MCPServerConfig] {
        configs.filter { $0.transport != .inProcess }
    }
    nonisolated static let appTrustHelp =
        "Runs in-process with access to the app's live state and auto-approves its tools without prompting. Irreversible actions still require your confirmation."
    nonisolated static let externalTrustHelp =
        "Auto-approves this server's tools without prompting. Irreversible actions still require your confirmation."
    nonisolated static func connectedBadgeText(toolCount: Int, resourceCount: Int) -> String {
        var parts: [String] = []
        if toolCount > 0 { parts.append("\(toolCount) tool\(toolCount == 1 ? "" : "s")") }
        if resourceCount > 0 { parts.append("\(resourceCount) resource\(resourceCount == 1 ? "" : "s")") }
        return parts.isEmpty ? "connected" : parts.joined(separator: " · ")
    }
}

/// Tools → MCP servers as DECLARED rows: one row per server — Off, On,
/// On and trusted, or Remove… — then one editor: a new server's fields, or an
/// existing server's secrets.
@MainActor
extension HostSettingsCatalog {
    static func mcpGroups(_ environment: AppEnvironment, page: SettingsPath) -> [SettingsGroup] {
        let store = environment.mcpServerRegistry.configStore
        let registry = environment.mcpServerRegistry
        let apps = MCPServerGrouping.appConfigs(from: store.all())
        var groups: [SettingsGroup] = []
        if !apps.isEmpty {
            let group = page.appending("apps")
            groups.append(SettingsGroup(
                path: group, title: "App servers",
                footerNote: "Ainkrad apps hosting their own MCP server in-process. Trusted: "
                    + MCPServerGrouping.appTrustHelp,
                fields: apps.map { serverRow(environment, $0, group: group, removable: false) }))
        }
        let group = page.appending("mcp")
        let externals = MCPServerGrouping.externalConfigs(from: store.all())
        var fields = externals.map { serverRow(environment, $0, group: group, removable: true) }
        fields += mcpEditor(environment, group: group, store: store, registry: registry, externals: externals)
        groups.append(SettingsGroup(
            path: group, title: "MCP servers",
            footerNote: "Model Context Protocol servers the assistant can call. Trusted: "
                + MCPServerGrouping.externalTrustHelp,
            fields: fields))
        return groups
    }

    private static func serverRow(_ environment: AppEnvironment, _ config: MCPServerConfig,
                                  group: SettingsPath, removable: Bool) -> SettingsField {
        let store = environment.mcpServerRegistry.configStore
        let registry = environment.mcpServerRegistry
        let tools = registry.discoveredTools().filter { $0.server == config.id }.count
        let resources = registry.discoveredResources().filter { $0.server == config.id }.count
        let health: String = switch registry.health[config.id] {
        case .connected: MCPServerGrouping.connectedBadgeText(toolCount: tools, resourceCount: resources)
        case .needsConfiguration: "Needs setup — add its secrets in Edit, below"
        case .failed: "Failed to connect"
        case .disabled, .none: "Off"
        }
        let target = config.transport == .stdio ? config.command : config.url?.absoluteString
        var options = [SettingsOption(id: "off", title: "Off"), SettingsOption(id: "on", title: "On"),
                       SettingsOption(id: "trusted", title: "On, trusted")]
        if removable { options.append(SettingsOption(id: "remove", title: "Remove…")) }
        return SettingsField(
            path: group.appending("server-\(config.id)"), label: config.displayName,
            help: [health, target].compactMap { $0 }.joined(separator: " · "),
            keywords: ["mcp", "server", config.id, config.displayName.lowercased()],
            kind: .select(options: options, selection: Binding(
                get: { !config.enabled ? "off" : config.trusted ? "trusted" : "on" },
                set: { choice in
                    if choice == "remove" {
                        if confirm("Remove \(config.displayName)?",
                                   "This deletes the server's configuration and any secrets stored for it. This can't be undone.",
                                   action: "Remove") {
                            store.remove(id: config.id)
                            Task { await registry.connectEnabled() }
                        }
                        return
                    }
                    store.setEnabled(choice != "off", for: config.id)
                    store.setTrusted(choice == "trusted", for: config.id)
                    Task { await registry.connectEnabled() }
                })))
    }

    private static func mcpEditor(_ environment: AppEnvironment, group: SettingsPath, store: MCPServerConfigStore,
                                  registry: MCPServerRegistry, externals: [MCPServerConfig]) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        var fields = [SettingsField(
            path: group.appending("edit"), label: "Edit",
            help: "Add a server over stdio or HTTPS, or set an existing server's secrets.",
            keywords: ["mcp", "add", "edit", "secret"],
            kind: .select(options: [SettingsOption(id: "", title: "New server…")]
                            + externals.map { SettingsOption(id: $0.id, title: $0.displayName) },
                          selection: Binding(get: { drafts.mcpSelection }, set: { drafts.mcpSelection = $0 })))]

        if let config = store.config(id: drafts.mcpSelection) {
            let keys = config.transport == .stdio ? config.envKeys : config.headerKeys
            let missing = Set(store.missingSecrets(for: config.id))
            guard !keys.isEmpty else {
                fields[0] = SettingsField(path: fields[0].path, label: fields[0].label,
                                          help: "\(config.displayName) declares no secrets.",
                                          keywords: fields[0].keywords, kind: fields[0].kind)
                return fields
            }
            for key in keys {
                let secretKey = MCPSecretKey(serverID: config.id, key: key)
                fields.append(SettingsField(
                    path: group.appending("secret-\(key)"), label: key,
                    help: missing.contains(key) ? "Not set" : "Set — type to replace it",
                    keywords: ["secret", key.lowercased()],
                    kind: .secure(Binding(get: { drafts.mcpSecrets[secretKey.keychainID] ?? "" },
                                          set: { drafts.mcpSecrets[secretKey.keychainID] = $0 }))))
            }
            fields.append(SettingsField(
                path: group.appending("secret-save"), label: "Save secrets",
                help: "Stored in your Keychain; the server reconnects.",
                kind: .action(title: "Save") {
                    for key in keys {
                        let secretKey = MCPSecretKey(serverID: config.id, key: key)
                        if let value = drafts.mcpSecrets[secretKey.keychainID], !value.isEmpty {
                            store.setSecret(value, for: secretKey)
                        }
                        drafts.mcpSecrets[secretKey.keychainID] = nil
                    }
                    Task { await registry.connectEnabled() }
                }))
            return fields
        }

        // A new server.
        let d = drafts.mcpNew
        func text(_ id: String, _ label: String, _ help: String, _ key: WritableKeyPath<MCPServerDraft, String>) -> SettingsField {
            SettingsField(path: group.appending("new-\(id)"), label: label, help: help,
                          kind: .text(Binding(get: { drafts.mcpNew[keyPath: key] },
                                              set: { drafts.mcpNew[keyPath: key] = $0 })))
        }
        fields.append(SettingsField(
            path: group.appending("new-transport"), label: "Connect over",
            kind: .select(options: [SettingsOption(id: MCPTransportKind.stdio.rawValue, title: "Stdio command"),
                                    SettingsOption(id: MCPTransportKind.httpSSE.rawValue, title: "HTTPS endpoint")],
                          selection: Binding(get: { drafts.mcpNew.transport.rawValue },
                                             set: { if let t = MCPTransportKind(rawValue: $0) { drafts.mcpNew.transport = t } }))))
        fields += [text("id", "Server ID", "Unique, e.g. github", \.id),
                   text("name", "Display name", "How it is listed.", \.name)]
        if d.transport == .stdio {
            fields += [text("command", "Command", "e.g. npx -y some-mcp-server", \.command),
                       text("args", "Arguments", "Comma-separated, optional.", \.args),
                       text("env", "Secret env vars", "Names only, comma-separated — values go in Edit once added.", \.envKeys)]
        } else {
            fields += [text("url", "URL", "https://…", \.url),
                       text("headers", "Secret headers", "Names only, comma-separated — values go in Edit once added.", \.headerKeys)]
        }
        let id = d.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let problem: String? =
            id.isEmpty ? "Enter a server ID."
            : store.config(id: id) != nil ? "\(id) is already configured."
            : d.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a display name."
            : d.transport == .stdio && d.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a command."
            : d.transport == .httpSSE && URL(string: d.url.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme == nil ? "Enter a URL."
            : nil
        let split = { (raw: String) in raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        fields.append(SettingsField(
            path: group.appending("new-add"), label: "Add server",
            help: problem ?? "Added switched off — turn it on in its row once its secrets are set.",
            kind: .action(title: "Add") {
                guard problem == nil else { return }
                let stdio = d.transport == .stdio
                store.upsert(MCPServerConfig(
                    id: id, displayName: d.name.trimmingCharacters(in: .whitespacesAndNewlines), transport: d.transport,
                    command: stdio ? d.command.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    args: stdio ? split(d.args) : [],
                    url: stdio ? nil : URL(string: d.url.trimmingCharacters(in: .whitespacesAndNewlines)),
                    envKeys: stdio ? split(d.envKeys) : [], headerKeys: stdio ? [] : split(d.headerKeys),
                    enabled: false, trusted: false))
                drafts.mcpNew = MCPServerDraft()
                drafts.mcpSelection = id
                Task { await registry.connectEnabled() }
            }))
        return fields
    }
}
