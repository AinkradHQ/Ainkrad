import SwiftUI
import AppKit
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Permissions & Sandbox → Tool hooks and Remote channel as DECLARED rows.
@MainActor
extension HostSettingsCatalog {
    // MARK: - Tool hooks

    /// One row per hook — On, Off, or Remove… — then the add form as rows.
    static func toolHookFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.toolHooksStore
        let drafts = environment.settingsDrafts
        var fields: [SettingsField] = store.hooks.map { hook in
            SettingsField(
                path: group.appending("hook-\(hook.id.uuidString)"),
                label: "\(hook.event == .preToolUse ? "Before" : "After") \(hook.match)",
                help: "\(hook.command) · \(hook.timeoutSeconds) s timeout",
                keywords: ["hook", hook.match.lowercased()],
                kind: .select(options: [SettingsOption(id: "on", title: "On"),
                                        SettingsOption(id: "off", title: "Off"),
                                        SettingsOption(id: "remove", title: "Remove…")],
                              selection: Binding(
                                get: { hook.enabled ? "on" : "off" },
                                set: { choice in
                                    if choice == "remove" {
                                        if confirm("Remove this hook?",
                                                   "“\(hook.command)” will no longer run \(hook.event == .preToolUse ? "before" : "after") \(hook.match).",
                                                   action: "Remove") {
                                            store.remove(id: hook.id)
                                        }
                                        return
                                    }
                                    var changed = hook
                                    changed.enabled = choice == "on"
                                    store.update(changed)
                                })))
        }
        let draft = drafts.hookDraft
        fields += [
            SettingsField(
                path: group.appending("new-event"), label: "New hook runs",
                help: "Before a call can block it; after a call sees its result.",
                keywords: ["hook", "pre", "post"],
                kind: .select(options: ToolHookEvent.allCases.map {
                    SettingsOption(id: $0.rawValue, title: $0 == .preToolUse ? "Before the tool" : "After the tool")
                }, selection: Binding(get: { drafts.hookDraft.event.rawValue },
                                      set: { if let e = ToolHookEvent(rawValue: $0) { drafts.hookDraft.event = e } }))),
            SettingsField(
                path: group.appending("new-match"), label: "Tool", help: "A tool name to match: edit_file, mcp/*, or *.",
                keywords: ["match", "tool"],
                kind: .text(Binding(get: { drafts.hookDraft.match }, set: { drafts.hookDraft.match = $0 }))),
            SettingsField(
                path: group.appending("new-command"), label: "Command",
                help: "A shell command. $AINKRAD_TOOL_PATH and friends are set for it.",
                keywords: ["command", "shell", "script"],
                kind: .text(Binding(get: { drafts.hookDraft.command }, set: { drafts.hookDraft.command = $0 }))),
            SettingsField(
                path: group.appending("new-timeout"), label: "Timeout",
                help: "\(draft.timeoutSeconds) s",
                keywords: ["timeout", "seconds"],
                kind: .slider(range: 10...600, step: 10, value: Binding(
                    get: { Double(drafts.hookDraft.timeoutSeconds) },
                    set: { drafts.hookDraft.timeoutSeconds = Int($0) }))),
            SettingsField(
                path: group.appending("new-add"), label: "Add hook",
                help: draft.validationError ?? "Ready to add.",
                kind: .action(title: "Add") {
                    guard let hook = drafts.hookDraft.build() else { return }
                    store.add(hook)
                    drafts.hookDraft = ToolHookDraft()
                }),
        ]
        return fields
    }

    // MARK: - Remote channel

    static func remoteChannelFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let settings = environment.remoteChannelSettingsStore
        let service = environment.remoteChannelService
        let status: String = switch service.status {
        case .off: "Disabled."
        case .needsToken: "Enabled — generate a token to start listening."
        case .listening: "Listening on 127.0.0.1:\(settings.settings.port) · POST /hook"
        case .stopped: "Stopped."
        }
        var fields = [
            SettingsField(
                path: group.appending("enabled"), label: "Enable remote channel",
                help: status,
                keywords: ["remote", "channel", "webhook", "listener"],
                kind: .toggle(Binding(get: { settings.settings.enabled },
                                      set: { settings.setEnabled($0); service.applyEnabledState() })),
                defaultDescription: "Off",
                isModified: { settings.settings.enabled },
                reset: { settings.setEnabled(false); service.applyEnabledState() }),
            SettingsField(
                path: group.appending("token"), label: settings.token == nil ? "Token" : "Rotate token",
                help: settings.token == nil ? "The listener starts once a token exists."
                                            : "A new token invalidates the old one.",
                keywords: ["token", "secret", "auth"],
                kind: .action(title: settings.token == nil ? "Generate" : "Rotate") {
                    _ = settings.rotateToken()
                    service.applyEnabledState()
                }),
        ]
        if settings.token != nil {
            fields.append(SettingsField(
                path: group.appending("clear"), label: "Clear token", help: "Stops the listener.",
                keywords: ["token", "clear"],
                kind: .action(title: "Clear") {
                    settings.clearToken()
                    service.applyEnabledState()
                }))
        }
        return fields
    }

    /// A native confirmation for a destructive declared action.
    static func confirm(_ title: String, _ message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
