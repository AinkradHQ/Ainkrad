import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// Permissions & Sandbox → Sandbox and Cloud as DECLARED rows: one row per
/// profile, New profile, one editor for the chosen user profile, and the
/// "why blocked or allowed?" explainer as a row.
@MainActor
extension HostSettingsCatalog {
    static func sandboxFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.sandboxProfileStore
        let drafts = environment.settingsDrafts
        let profiles = store.all()
        let isBuiltIn = { (p: SandboxProfile) in BuiltInSandboxProfiles.reservedIDs.contains(p.id) }

        var fields: [SettingsField] = profiles.map { profile in
            let builtIn = isBuiltIn(profile)
            var options = [SettingsOption(id: "keep", title: builtIn ? "Built-in" : "Saved")]
            if !builtIn {
                options += [SettingsOption(id: "edit", title: "Edit"), SettingsOption(id: "delete", title: "Delete…")]
            }
            return SettingsField(
                path: group.appending("profile-\(profile.id)"), label: profile.name,
                help: sandboxSummary(profile),
                keywords: ["sandbox", "profile", profile.name.lowercased()],
                kind: .select(
                    options: options,
                    selection: Binding(
                        get: { drafts.sandboxDraft?.id == profile.id ? "edit" : "keep" },
                        set: { choice in
                            switch choice {
                            case "edit": editSandbox(profile, drafts)
                            case "delete":
                                if confirm(
                                    "Delete \(profile.name)?",
                                    "This user-defined profile will be removed. This can't be undone.",
                                    action: "Delete")
                                {
                                    store.delete(id: profile.id)
                                    if drafts.sandboxDraft?.id == profile.id { drafts.sandboxDraft = nil }
                                }
                            default:
                                if drafts.sandboxDraft?.id == profile.id { drafts.sandboxDraft = nil }
                            }
                        })))
        }
        fields.append(
            SettingsField(
                path: group.appending("new"), label: "New profile",
                help: "Built-in profiles can't be edited — start a profile of your own.",
                keywords: ["sandbox", "profile", "new", "add"],
                kind: .action(title: "New") {
                    let fresh = SandboxProfileFactory.blank()
                    store.upsert(fresh)
                    editSandbox(fresh, drafts)
                }))

        if let draft = drafts.sandboxDraft {
            fields += sandboxEditor(draft, store: store, drafts: drafts, group: group)
        }

        // Explainer.
        let permissions = environment.agentPermissionStore
        let explained = drafts.sandboxDraft ?? BuiltInSandboxProfiles.workspaceWrite
        let explanation = SandboxPolicyExplainer.explain(
            profile: explained, toolName: drafts.sandboxExplainTool,
            mode: permissions.mode, allowlist: permissions.allowlist, gateReads: permissions.gateReads)
        fields.append(
            SettingsField(
                path: group.appending("explain"), label: "Why blocked or allowed?",
                help: "\(explanation.reason) (for \(explained.name))",
                keywords: ["explain", "blocked", "allowed", "why", "sandbox"],
                kind: .select(
                    options: SandboxPolicyExplainer.sampleToolNames.map { SettingsOption(id: $0, title: $0) },
                    selection: Binding(
                        get: { drafts.sandboxExplainTool },
                        set: { drafts.sandboxExplainTool = $0 }))))
        return fields
    }

    private static func sandboxEditor(
        _ draft: SandboxProfile, store: SandboxProfileStore,
        drafts: HostSettingsDrafts, group: SettingsPath
    ) -> [SettingsField] {
        let edit = group.appending("edit")
        func setDraft(_ change: (inout SandboxProfile) -> Void) {
            guard var d = drafts.sandboxDraft else { return }
            change(&d)
            drafts.sandboxDraft = d
        }
        func list(_ raw: String) -> [String] {
            raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var fields = [
            SettingsField(
                path: edit.appending("name"), label: "Profile name", help: "Editing this profile.",
                kind: .text(Binding(get: { drafts.sandboxDraft?.name ?? "" }, set: { v in setDraft { $0.name = v } }))),
            SettingsField(
                path: edit.appending("backend"), label: "Backend",
                kind: .select(
                    options: SandboxBackendKind.allCases.map { SettingsOption(id: $0.rawValue, title: $0.rawValue) },
                    selection: Binding(
                        get: { drafts.sandboxDraft?.backend.rawValue ?? "" },
                        set: { v in if let b = SandboxBackendKind(rawValue: v) { setDraft { $0.backend = b } } }))),
            SettingsField(
                path: edit.appending("readable"), label: "Readable paths", help: "Comma-separated.",
                kind: .text(Binding(get: { drafts.sandboxReadable }, set: { drafts.sandboxReadable = $0 }))),
            SettingsField(
                path: edit.appending("writable"), label: "Writable paths", help: "Comma-separated.",
                kind: .text(Binding(get: { drafts.sandboxWritable }, set: { drafts.sandboxWritable = $0 }))),
            SettingsField(
                path: edit.appending("network"), label: "Network",
                kind: .select(
                    options: NetworkMode.allCases.map { SettingsOption(id: $0.rawValue, title: $0.title) },
                    selection: Binding(
                        get: { NetworkModeMapping.mode(for: draft.networkPolicy).rawValue },
                        set: { v in
                            guard let mode = NetworkMode(rawValue: v) else { return }
                            setDraft {
                                $0.networkPolicy = NetworkModeMapping.policy(
                                    for: mode, hosts: list(drafts.sandboxHosts))
                            }
                        }))),
        ]
        if NetworkModeMapping.mode(for: draft.networkPolicy) == .allowList {
            fields.append(
                SettingsField(
                    path: edit.appending("hosts"), label: "Allowed hosts", help: "Comma-separated.",
                    kind: .text(Binding(get: { drafts.sandboxHosts }, set: { drafts.sandboxHosts = $0 }))))
        }
        fields += [
            SettingsField(
                path: edit.appending("timeout"), label: "Timeout",
                help: "\(draft.resourceLimits.timeoutSeconds) s before a sandboxed run is killed.",
                kind: .slider(
                    range: 5...600, step: 5,
                    value: Binding(
                        get: { Double(drafts.sandboxDraft?.resourceLimits.timeoutSeconds ?? 60) },
                        set: { v in setDraft { $0.resourceLimits.timeoutSeconds = Int(v) } }))),
            SettingsField(
                path: edit.appending("tools"), label: "Tool allow-list",
                help: "Comma-separated; empty defers to the other permission layers. e.g. "
                    + SandboxPolicyExplainer.sampleToolNames.prefix(3).joined(separator: ", "),
                kind: .text(Binding(get: { drafts.sandboxTools }, set: { drafts.sandboxTools = $0 }))),
            SettingsField(
                path: edit.appending("host-override"), label: "Allow host override (dangerous)",
                help: "Lets a non-main trust tier (background, scheduled, subagent, untrusted MCP) run "
                    + "unsandboxed on the host. Leave off unless you know why you need it.",
                kind: .toggle(
                    Binding(
                        get: { drafts.sandboxDraft?.allowHostOverride ?? false },
                        set: { v in setDraft { $0.allowHostOverride = v } }))),
            SettingsField(
                path: edit.appending("save"), label: "Save profile", help: "Keeps these changes.",
                kind: .action(title: "Save") {
                    setDraft {
                        $0.fsPolicy.readablePaths = list(drafts.sandboxReadable)
                        $0.fsPolicy.writablePaths = list(drafts.sandboxWritable)
                        $0.toolAllowList = Set(list(drafts.sandboxTools))
                        if case .allowList = $0.networkPolicy {
                            $0.networkPolicy = .allowList(list(drafts.sandboxHosts))
                        }
                    }
                    if let saved = drafts.sandboxDraft {
                        store.upsert(saved)
                        editSandbox(saved, drafts)
                    }
                }),
            SettingsField(
                path: edit.appending("discard"), label: "Discard changes", help: "Back to the saved profile.",
                kind: .action(title: "Discard") {
                    if let id = drafts.sandboxDraft?.id, let saved = store.profile(id: id) {
                        editSandbox(saved, drafts)
                    }
                }),
        ]
        return fields
    }

    private static func editSandbox(_ profile: SandboxProfile, _ drafts: HostSettingsDrafts) {
        drafts.sandboxDraft = profile
        drafts.sandboxReadable = profile.fsPolicy.readablePaths.joined(separator: ", ")
        drafts.sandboxWritable = profile.fsPolicy.writablePaths.joined(separator: ", ")
        drafts.sandboxTools = profile.toolAllowList.sorted().joined(separator: ", ")
        if case .allowList(let hosts) = profile.networkPolicy {
            drafts.sandboxHosts = hosts.joined(separator: ", ")
        } else {
            drafts.sandboxHosts = ""
        }
    }

    private static func sandboxSummary(_ p: SandboxProfile) -> String {
        let network: String =
            switch p.networkPolicy {
            case .off: "off"
            case .on: "on"
            case .allowList(let hosts): "allow \(hosts.count)"
            }
        return
            "\(p.backend.rawValue) · read \(p.fsPolicy.readablePaths.count) / write \(p.fsPolicy.writablePaths.count) · "
            + "network \(network) · \(p.resourceLimits.timeoutSeconds) s"
            + (p.allowHostOverride ? " · HOST OVERRIDE" : "")
    }

    // MARK: - Cloud

    static func cloudFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.cloudCredentialsStore
        let drafts = environment.settingsDrafts
        return CloudProvider.allCases.map { provider in
            let name: String =
                switch provider {
                case .modal: "Modal"
                case .daytona: "Daytona"
                case .singularity: "Singularity"
                }
            let key = "cloud.\(provider)"
            return SettingsField(
                path: group.appending("\(provider)"), label: name, help: "\(name) token, kept in your Keychain.",
                keywords: ["cloud", "token", name.lowercased()],
                kind: .secure(
                    Binding(
                        get: { drafts.text[key] ?? store.credential(for: provider) ?? "" },
                        set: {
                            drafts.text[key] = $0
                            store.setCredential($0.isEmpty ? nil : $0, for: provider)
                        })))
        }
    }
}
