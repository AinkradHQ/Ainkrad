import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// The agent stack, flattened out of the Sage's former pill bar into
/// sibling pages. This collapses the deepest path in the app from four
/// levels to two and puts MCP/LSP/Skills/Memory beside the model and
/// permissions they actually serve.
///
/// The Sage's own section builders are unchanged — they are wrapped as
/// `.custom` fields here. What went away is the nested tab bar, not the UI.
@MainActor
enum IntelligenceSettingsCatalog {
    static func pages(environment: AppEnvironment) -> [SettingsPage] {
        [
            modelAndConnections(environment),
            permissionsAndSandbox(environment),
            memory(environment),
            skills(environment),
            tools(environment),
            privacyAndData(environment),
        ]
    }

    // MARK: - Model & Connections

    private static func modelAndConnections(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["intelligence", "model"])
        return SettingsPage(
            path: page, title: "Model & Connections", icon: "brain",
            group: .intelligence, order: 0,
            groups: [
                SettingsGroup(
                    path: page.appending("connections"), title: "Connections",
                    footerNote: "Providers, base URLs, and API keys the assistant can reach.",
                    fields: HostSettingsCatalog.connectionFields(environment, group: page.appending("connections"))),
                SettingsGroup(
                    path: page.appending("picker"), title: "Model",
                    fields: HostSettingsCatalog.modelFields(environment, group: page.appending("picker"))),
            ])
    }

    // MARK: - Permissions & Sandbox

    private static func permissionsAndSandbox(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["intelligence", "permissions"])
        return SettingsPage(
            path: page, title: "Permissions & Sandbox", icon: "lock.shield",
            group: .intelligence, order: 1,
            groups: [
                SettingsGroup(
                    path: page.appending("permissions"), title: "Permissions",
                    fields: HostSettingsCatalog.agentPermissionFields(environment, group: page.appending("permissions"))
                ),
                SettingsGroup(
                    path: page.appending("sandbox"), title: "Sandbox",
                    footerNote: "Trust-tier defaults: the main session runs on the host (trusted); "
                        + "background, scheduled, subagent and untrusted-MCP runs get Workspace write "
                        + "with the network off.",
                    fields: HostSettingsCatalog.sandboxFields(environment, group: page.appending("sandbox"))),
                SettingsGroup(
                    path: page.appending("cloud"), title: "Cloud",
                    footerNote: "Cloud execution is opt-in per Agent — enable it on an Agent's profile.",
                    fields: HostSettingsCatalog.cloudFields(environment, group: page.appending("cloud"))),
                SettingsGroup(
                    path: page.appending("hooks"), title: "Tool hooks",
                    footerNote: "Run a shell command before or after a tool call; a hook that runs "
                        + "before can block the call.",
                    fields: HostSettingsCatalog.toolHookFields(environment, group: page.appending("hooks"))),
                SettingsGroup(
                    path: page.appending("remote"), title: "Remote channel",
                    footerNote: "Drive this agent off-machine over a local, token-authenticated HTTP "
                        + "endpoint. Off by default; binds to 127.0.0.1 only.",
                    fields: HostSettingsCatalog.remoteChannelFields(environment, group: page.appending("remote"))),
            ])
    }

    // MARK: - Memory

    private static func memory(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["intelligence", "memory"])
        return SettingsPage(
            path: page, title: "Memory", icon: "brain",
            group: .intelligence, order: 2,
            groups: HostSettingsCatalog.memoryGroups(environment, page: page))
    }

    // MARK: - Skills

    private static func skills(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["intelligence", "skills"])
        return SettingsPage(
            path: page, title: "Skills", icon: "sparkles",
            group: .intelligence, order: 3,
            groups: HostSettingsCatalog.skillGroups(environment, page: page),
            // Evaluated per render, not snapshotted at catalog-build time:
            // proposals can land while the Settings overlay is open, and this
            // badge is the only signal anywhere in the app that any are waiting.
            badge: { environment.skillRegistry.proposals().count })
    }

    // MARK: - Tools

    private static func tools(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["intelligence", "tools"])
        return SettingsPage(
            path: page, title: "Tools", icon: "point.3.connected.trianglepath.dotted",
            group: .intelligence, order: 4,
            groups: HostSettingsCatalog.mcpGroups(environment, page: page) + [
                SettingsGroup(
                    path: page.appending("lsp"), title: "Language servers",
                    footerNote: "LSP servers backing code intelligence.",
                    fields: HostSettingsCatalog.lspFields(environment, group: page.appending("lsp"))),
                SettingsGroup(
                    path: page.appending("web"), title: "Web search",
                    fields: HostSettingsCatalog.webSearchFields(environment, group: page.appending("web"))),
                SettingsGroup(
                    path: page.appending("images"), title: "Images",
                    fields: HostSettingsCatalog.imageFields(environment, group: page.appending("images"))),
                SettingsGroup(
                    path: page.appending("video"), title: "Video",
                    fields: HostSettingsCatalog.videoFields(environment, group: page.appending("video"))),
            ])
    }

    // MARK: - Privacy & Data

    private static func privacyAndData(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["intelligence", "privacy"])
        return SettingsPage(
            path: page, title: "Privacy & Data", icon: "eye.slash",
            group: .intelligence, order: 5,
            groups: [
                SettingsGroup(
                    path: page.appending("context"), title: "Context privacy",
                    footerNote: "What the assistant is allowed to read from your workspace.",
                    fields: HostSettingsCatalog.contextPrivacyFields(environment, group: page.appending("context")))
            ])
    }
}
