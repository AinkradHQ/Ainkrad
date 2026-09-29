import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Model & Connections → Connections as DECLARED rows: one row per
/// connection (Saved, Test or Remove…), then one editor — a new connection,
/// or a Claude connection's subscription sign-in.
@MainActor
extension HostSettingsCatalog {
    static func connectionFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let store = environment.connectionStore
        let drafts = environment.settingsDrafts
        _ = drafts.revision

        var fields: [SettingsField] = store.connections.map { connection in
            let preset = ProviderPreset.preset(id: connection.presetID)
            let what = connection.authMode == .subscription ? "Claude subscription"
                : preset.requiresKey ? "API key set" : connection.baseURL
            return SettingsField(
                path: group.appending("connection-\(connection.id.uuidString)"), label: connection.displayName,
                help: [what, drafts.connectionTests[connection.id]].compactMap { $0 }.joined(separator: " · "),
                keywords: ["connection", "provider", "api key", "token", connection.displayName.lowercased()],
                kind: .select(options: [SettingsOption(id: "keep", title: "Saved"),
                                        SettingsOption(id: "test", title: "Test"),
                                        SettingsOption(id: "remove", title: "Remove…")],
                              selection: Binding(get: { "keep" }, set: { choice in
                                  switch choice {
                                  case "test": testConnection(connection, environment)
                                  case "remove":
                                      if confirm("Remove \(connection.displayName)?",
                                                 "Its saved key or sign-in is deleted.", action: "Remove") {
                                          store.removeConnection(connection)
                                          if drafts.connectionSelection == connection.id.uuidString {
                                              drafts.connectionSelection = ""
                                          }
                                      }
                                  default: break
                                  }
                              })))
        }

        let claude = store.connections.filter { $0.kind == .claude }
        fields.append(SettingsField(
            path: group.appending("edit"), label: "Edit",
            help: "Add a connection, or manage a Claude connection's sign-in.",
            keywords: ["connection", "add", "api key", "sign in", "subscription"],
            kind: .select(options: [SettingsOption(id: "", title: "New connection…")]
                            + claude.map { SettingsOption(id: $0.id.uuidString, title: $0.displayName) },
                          selection: Binding(get: { drafts.connectionSelection },
                                             set: { drafts.connectionSelection = $0 }))))
        if let connection = claude.first(where: { $0.id.uuidString == drafts.connectionSelection }) {
            fields += subscriptionFields(connection, environment, group: group)
        } else {
            fields += newConnectionFields(environment, group: group)
        }
        return fields
    }

    private static func testConnection(_ connection: Connection, _ environment: AppEnvironment) {
        let drafts = environment.settingsDrafts
        drafts.connectionTests[connection.id] = "Testing…"
        Task {
            let credential: ProviderCredential
            if connection.authMode == .subscription {
                credential = (try? await environment.oauthStore.liveCredential(for: connection)) ?? .apiKey("")
            } else {
                credential = .apiKey(environment.connectionStore.token(for: connection) ?? "")
            }
            let result = await environment.modelCatalogService.test(
                kind: connection.kind, baseURL: connection.baseURL, credential: credential)
            drafts.connectionTests[connection.id] = result.ok ? "✓ \(result.message)" : "✗ \(result.message)"
        }
    }

    private static func newConnectionFields(_ environment: AppEnvironment, group: SettingsPath) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        let preset = ProviderPreset.preset(id: drafts.newConnectionPreset)
        if drafts.newConnectionURL.isEmpty { drafts.newConnectionURL = preset.defaultBaseURL }
        let subscription = preset.kind == .claude && drafts.newConnectionSubscription
        var fields = [
            SettingsField(
                path: group.appending("new-provider"), label: "Provider",
                keywords: ["provider", "openai", "anthropic", "openrouter"],
                kind: .select(options: ProviderPreset.all.map { SettingsOption(id: $0.id, title: $0.displayName) },
                              selection: Binding(get: { drafts.newConnectionPreset }, set: { id in
                                  let chosen = ProviderPreset.preset(id: id)
                                  drafts.newConnectionPreset = id
                                  drafts.newConnectionURL = chosen.defaultBaseURL
                                  if chosen.kind != .claude { drafts.newConnectionSubscription = false }
                              }))),
            SettingsField(
                path: group.appending("new-name"), label: "Name", help: "Defaults to \(preset.displayName).",
                kind: .text(Binding(get: { drafts.newConnectionName }, set: { drafts.newConnectionName = $0 }))),
        ]
        if preset.kind == .claude {
            fields.append(SettingsField(
                path: group.appending("new-auth"), label: "Sign in with",
                kind: .select(options: [SettingsOption(id: "key", title: "API key"),
                                        SettingsOption(id: "subscription", title: "Claude subscription")],
                              selection: Binding(get: { drafts.newConnectionSubscription ? "subscription" : "key" },
                                                 set: { drafts.newConnectionSubscription = $0 == "subscription" }))))
        }
        if preset.allowsBaseURLEdit {
            fields.append(SettingsField(
                path: group.appending("new-url"), label: "Base URL",
                kind: .text(Binding(get: { drafts.newConnectionURL }, set: { drafts.newConnectionURL = $0 }))))
        }
        if preset.requiresKey && !subscription {
            fields.append(SettingsField(
                path: group.appending("new-key"), label: "API key", help: "Kept in your Keychain.",
                kind: .secure(Binding(get: { drafts.newConnectionKey }, set: { drafts.newConnectionKey = $0 }))))
        }
        let hasKey = !drafts.newConnectionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasURL = !drafts.newConnectionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let problem: String? = !hasURL ? "Enter a base URL."
            : (preset.requiresKey && !subscription && !hasKey) ? "Enter an API key." : nil
        fields.append(SettingsField(
            path: group.appending("new-add"), label: "Add connection",
            help: problem ?? (subscription ? "Adds it, then sign in from Edit." : "Ready to add."),
            kind: .action(title: "Add") {
                guard problem == nil else { return }
                let created = environment.connectionStore.addConnection(
                    preset: preset,
                    displayName: drafts.newConnectionName.isEmpty ? preset.displayName : drafts.newConnectionName,
                    baseURL: drafts.newConnectionURL, token: subscription ? "" : drafts.newConnectionKey,
                    authMode: subscription ? .subscription : .apiKey)
                drafts.newConnectionName = ""; drafts.newConnectionKey = ""
                drafts.newConnectionSubscription = false
                drafts.modelPicker().refreshModels(for: created, environment)
                if subscription { drafts.connectionSelection = created.id.uuidString }
            }))
        return fields
    }

    private static func subscriptionFields(_ connection: Connection, _ environment: AppEnvironment,
                                           group: SettingsPath) -> [SettingsField] {
        let drafts = environment.settingsDrafts
        let store = environment.connectionStore
        let oauth = environment.oauthStore
        let controller = drafts.oauthControllers[connection.id] ?? {
            let made = ClaudeOAuthLoginController(store: oauth, flow: ClaudeOAuthFlow(clientVersion: ClaudeProvider.claudeCodeVersion))
            drafts.oauthControllers[connection.id] = made
            return made
        }()
        let settle = { drafts.revision += 1 }
        var fields = [SettingsField(
            path: group.appending("auth"), label: "Sign in with",
            kind: .select(options: [SettingsOption(id: AuthMode.apiKey.rawValue, title: "API key"),
                                    SettingsOption(id: AuthMode.subscription.rawValue, title: "Claude subscription")],
                          selection: Binding(get: { connection.authMode.rawValue },
                                             set: { if let m = AuthMode(rawValue: $0) { store.setAuthMode(m, for: connection); settle() } })))]
        guard connection.authMode == .subscription else { return fields }
        if let account = oauth.account(for: connection.id) {
            fields.append(SettingsField(
                path: group.appending("account"), label: "Claude account",
                help: account.source == .claudeCodeImport ? "Imported from Claude Code." : "Signed in.",
                kind: .action(title: "Sign out") { oauth.signOut(connection.id); settle() }))
            return fields
        }
        fields.append(SettingsField(
            path: group.appending("sign-in"), label: "Sign in with Claude",
            help: controller.errorMessage ?? "Opens your browser to sign in.",
            kind: .action(title: "Sign in") { Task { await controller.beginLogin(for: connection); settle() } }))
        if controller.usePasteFallback {
            fields += [
                SettingsField(path: group.appending("paste"), label: "Redirect URL or code",
                              help: "If the browser could not return to Ainkrad, paste what it shows.",
                              kind: .secure(Binding(get: { drafts.connectionPaste }, set: { drafts.connectionPaste = $0 }))),
                SettingsField(path: group.appending("paste-submit"), label: "Finish sign-in",
                              kind: .action(title: "Submit") {
                                  let raw = drafts.connectionPaste
                                  drafts.connectionPaste = ""
                                  Task { await controller.pasteCode(raw, for: connection); settle() }
                              }),
            ]
        }
        if controller.canImportFromClaudeCode {
            fields.append(SettingsField(
                path: group.appending("import"), label: "Use your Claude Code login",
                help: "Reuses the sign-in Claude Code already has on this Mac.",
                kind: .action(title: "Use") { controller.importFromClaudeCode(for: connection); settle() }))
        }
        return fields
    }
}
