import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// The assistant's Model, Permissions and Context privacy as DECLARED rows,
/// and Sage's own app page (its appearance) as the host's Appearance tab.
@MainActor
extension HostSettingsCatalog {
    // MARK: - Model

    static func modelFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        let picker = drafts.modelPicker()
        let store = environment.connectionStore
        let config = environment.agentConfigStore
        guard !store.connections.isEmpty else {
            return [
                SettingsField(
                    path: group.appending("none"), label: "Model",
                    help: "Add a connection first — the Connections tab — to choose a model.",
                    kind: .shortcut(.constant("No connection")))
            ]
        }
        let active = picker.activeConnection(environment)
        if let active, drafts.modelsFetchedFor != active.id {
            drafts.modelsFetchedFor = active.id
            picker.refreshModels(for: active, environment)
        }
        var fields = [
            SettingsField(
                path: group.appending("connection"), label: "Connection",
                help: "Which connection answers.",
                keywords: ["connection", "provider"],
                kind: .select(
                    options: store.connections.map { SettingsOption(id: $0.id.uuidString, title: $0.displayName) },
                    selection: Binding(
                        get: { (active ?? store.connections[0]).id.uuidString },
                        set: { id in
                            if let connection = store.connections.first(where: { $0.id.uuidString == id }) {
                                picker.selectConnection(connection, environment)
                            }
                        }))),
            SettingsField(
                path: group.appending("model"), label: "Model",
                help: picker.isRefreshing ? "Fetching the connection's models…" : "The model that answers.",
                keywords: ["model", "llm"],
                kind: .select(
                    options: picker.modelOptions(for: active, environment).map { SettingsOption(id: $0, title: $0) },
                    selection: Binding(get: { config.current.model }, set: { config.setModel($0) }))),
            SettingsField(
                path: group.appending("refresh"), label: "Refresh models",
                help: "Ask the connection for its current model list.",
                keywords: ["refresh", "models"],
                kind: .action(title: "Refresh") {
                    if let active { picker.refreshModels(for: active, environment, force: true) }
                }),
        ]
        if active?.kind == .claude {
            fields.append(
                SettingsField(
                    path: group.appending("effort"), label: "Effort",
                    help: "How much reasoning effort it spends.",
                    keywords: ["effort", "reasoning", "thinking"],
                    kind: .select(
                        options: ["low", "medium", "high", "xhigh"].map {
                            SettingsOption(id: $0, title: $0.capitalized)
                        },
                        selection: Binding(get: { config.current.effort }, set: { config.setEffort($0) }))))
        }
        return fields
    }

    // MARK: - Permissions

    static func agentPermissionFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.agentPermissionStore
        let modeTitle = { (mode: AgentPermissionMode) -> String in
            switch mode {
            case .ask: "Ask"
            case .autoApprove: "Auto-approve"
            case .fullAuto: "Full-auto"
            }
        }
        var fields = [
            SettingsField(
                path: group.appending("mode"), label: "Default mode",
                help: "What the assistant may do without asking.",
                keywords: ["approve", "allow", "deny", "ask", "auto", "full-auto", "permission"],
                kind: .select(
                    options: AgentPermissionMode.allCases.map { SettingsOption(id: $0.rawValue, title: modeTitle($0)) },
                    selection: Binding(
                        get: { store.mode.rawValue },
                        set: { if let m = AgentPermissionMode(rawValue: $0) { store.setMode(m) } }))),
            SettingsField(
                path: group.appending("gate-reads"), label: "Ask before reading files",
                help: "The assistant asks before reading any file (except in Full-auto).",
                keywords: ["read", "files", "ask"],
                kind: .toggle(Binding(get: { store.gateReads }, set: { store.setGateReads($0) })),
                defaultDescription: "Off",
                isModified: { store.gateReads },
                reset: { store.setGateReads(false) }),
        ]
        let allowed = store.allowlist.sorted()
        if allowed.isEmpty {
            fields.append(
                SettingsField(
                    path: group.appending("allowed-none"), label: "Always-allowed tools",
                    help: "None yet. Use “Allow always” on an approval to add one.",
                    kind: .shortcut(.constant("None"))))
        } else {
            fields += allowed.map { name in
                SettingsField(
                    path: group.appending("allowed-\(name)"), label: ToolPresentation.humanize(name),
                    help: "Always allowed · \(name)", keywords: ["allowlist", "always", name.lowercased()],
                    kind: .action(title: "Remove") { store.removeFromAllowlist(name) })
            }
            fields.append(
                SettingsField(
                    path: group.appending("allowed-clear"), label: "Clear always-allowed tools",
                    help: "Every tool asks again, per the default mode.",
                    kind: .action(title: "Clear all") {
                        if confirm("Clear always-allowed tools?", "Every tool will ask again.", action: "Clear") {
                            store.clearAllowlist()
                        }
                    }))
        }
        return fields
    }

    // MARK: - Context privacy

    static func contextPrivacyFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.agentContextSettingsStore
        return [
            ("terminal", "Terminal buffers", "Recent output from open Terminal Blocks."),
            ("git", "Git status", "Branch, staged/unstaged changes, and recent commits."),
            ("repo-instructions", "Repo instruction files", "CLAUDE.md / AGENTS.md found in the working repo."),
        ]
        .map { kind, label, help in
            SettingsField(
                path: group.appending(kind), label: label, help: help,
                keywords: ["context", "privacy", label.lowercased()],
                kind: .toggle(
                    Binding(
                        get: { store.isEnabled(kind: kind) },
                        set: { store.setEnabled($0, for: kind) })))
        }
    }

    // MARK: - Sage's own page

    /// Sage's appearance. Titled "Appearance" so `AppSettingsCatalog` merges
    /// it into the page's one Appearance tab, after Open as / Open in.
    static func sageAppearanceGroup(_ environment: AppEnvironment, root: SettingsPath) -> SettingsGroup {
        let appearance = environment.appAppearanceStore
        let manager = environment.themeManager
        let id = SageApp.id
        let group = root.appending("appearance")
        return SettingsGroup(
            path: group, title: "Appearance",
            footerNote:
                "Applies to the assistant's messages only; text left matching Appearance inherits the app-wide setting.",
            fields: [
                SettingsField(
                    path: group.appending("opacity"), label: "Surface opacity",
                    help: "\(Int(appearance.surfaceOpacity(id) * 100))%. Lower lets the workspace show through.",
                    keywords: ["opacity", "transparency", "translucent"],
                    kind: .slider(
                        range: 0.3...1.0, step: 0.05,
                        value: Binding(
                            get: { appearance.surfaceOpacity(id) }, set: { appearance.setSurfaceOpacity(id, $0) })),
                    defaultDescription: "100%",
                    isModified: { appearance.surfaceOpacity(id) != 1.0 },
                    reset: { appearance.setSurfaceOpacity(id, 1.0) }),
                SettingsField(
                    path: group.appending("blur"), label: "Blur",
                    help: "Blur the workspace revealed behind this app when it's translucent.",
                    keywords: ["blur", "backdrop"],
                    kind: .toggle(
                        Binding(get: { appearance.blurEnabled(id) }, set: { appearance.setBlurEnabled(id, $0) })),
                    defaultDescription: "Off",
                    isModified: { appearance.blurEnabled(id) },
                    reset: { appearance.setBlurEnabled(id, false) }),
                SettingsField(
                    path: group.appending("font"), label: "Text font",
                    keywords: ["font", "typeface"],
                    kind: .select(
                        options: UIFontFamily.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                        selection: Binding(
                            get: { (appearance.fontFamily(id) ?? manager.uiFontFamily).rawValue },
                            set: { appearance.setFontFamily(id, UIFontFamily(rawValue: $0)) })),
                    defaultDescription: "Appearance's",
                    isModified: { appearance.fontFamily(id) != nil },
                    reset: { appearance.setFontFamily(id, nil) }),
                SettingsField(
                    path: group.appending("size"), label: "Text size",
                    keywords: ["font", "size", "scale"],
                    kind: .select(
                        options: UIFontScale.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                        selection: Binding(
                            get: { (appearance.fontScale(id) ?? manager.uiFontScale).rawValue },
                            set: { appearance.setFontScale(id, UIFontScale(rawValue: $0)) })),
                    defaultDescription: "Appearance's",
                    isModified: { appearance.fontScale(id) != nil },
                    reset: { appearance.setFontScale(id, nil) }),
            ])
    }
}
