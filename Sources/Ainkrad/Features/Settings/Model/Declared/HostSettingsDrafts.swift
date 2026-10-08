import AinkradHostRuntime
import AppKit
import SwiftUI

/// What a declared host page must remember between rebuilds (the settings
/// overlay rebuilds its catalog on every render): text being typed that is
/// only saved once it is complete, and values that are costly to read per
/// render. One per environment.
@MainActor @Observable
final class HostSettingsDrafts {
    /// "You" fields as typed. Saving trims, so binding a row straight to the
    /// store would eat the space between two words the moment it was typed.
    var profile: [String: String]?
    /// The speech store the Speech rows edit — built once, not per render.
    @ObservationIgnored private var speechStore: SpeechSynthesisSettingsStore?
    var speechAPIKey: String?
    var speechVoice: String?
    var speechModel: String?
    var speechBaseURL: String?
    @ObservationIgnored var homePath: URL??
    /// Language servers' editor: which server it shows ("" = a new one) and
    /// the fields as typed.
    var lspSelection = ""
    var lspID = ""
    var lspCommand = ""
    var lspArgs = ""
    var lspGlobs = ""
    /// MCP servers' editor: which server ("" = a new one), the new server's
    /// fields, and secret values typed but not yet saved (by Keychain id).
    var mcpSelection = ""
    var mcpNew = MCPServerDraft()
    var mcpSecrets: [String: String] = [:]
    /// Skills' logic (drafts, bind errors) and the command being bound.
    @ObservationIgnored private var skillsModel: SkillsManagerViewModel?
    var newCommand = ""
    var newCommandSkill = ""

    func skills(_ environment: AppEnvironment) -> SkillsManagerViewModel {
        if let skillsModel { return skillsModel }
        let made = SkillsManagerViewModel(
            registry: environment.skillRegistry, store: environment.skillCommandStore,
            resyncCommands: { [weak environment] in environment?.resyncSkillCommands() })
        skillsModel = made
        return made
    }
    /// Sandbox's editor: the user profile being edited (nil = none chosen)
    /// and its list fields as typed.
    var sandboxDraft: SandboxProfile?
    var sandboxReadable = ""
    var sandboxWritable = ""
    var sandboxHosts = ""
    var sandboxTools = ""
    var sandboxExplainTool = SandboxPolicyExplainer.sampleToolNames[0]
    /// The model picker the Model rows read, and the connection it last
    /// fetched models for (refetched when the active connection changes).
    @ObservationIgnored private var modelPickerModel: SageModelPickerModel?
    @ObservationIgnored var modelsFetchedFor: UUID?

    func modelPicker() -> SageModelPickerModel {
        if let modelPickerModel { return modelPickerModel }
        let made = SageModelPickerModel()
        modelPickerModel = made
        return made
    }
    /// Connections: the editor's selection ("" = a new connection), the new
    /// connection's fields, test results, and one sign-in controller per
    /// Claude connection. `revision` re-renders after async sign-in steps,
    /// since the controller is an ObservableObject the catalog doesn't observe.
    var connectionSelection = ""
    var newConnectionPreset = "openai"
    var newConnectionName = ""
    var newConnectionURL = ""
    var newConnectionKey = ""
    var newConnectionSubscription = false
    var connectionPaste = ""
    var connectionTests: [UUID: String] = [:]
    var revision = 0
    @ObservationIgnored var oauthControllers: [UUID: ClaudeOAuthLoginController] = [:]
    /// Notifications: the source whose details the editor shows ("" = none),
    /// and the stats window.
    var notificationSource = ""
    var healthWindow: NotificationStats.Window = .week
    /// The tool hook being composed on Permissions → Tool hooks.
    var hookDraft = ToolHookDraft()
    /// Typed-but-unsaved text for the generation tools' rows, keyed by row id.
    var text: [String: String] = [:]
    @ObservationIgnored private var videoStore: VideoSettingsStore?

    func video(_ persistence: PersistenceStore) -> VideoSettingsStore {
        if let videoStore { return videoStore }
        let made = VideoSettingsStore(persistence: persistence)
        videoStore = made
        return made
    }
    /// A destructive declared action waiting for the user's answer. The
    /// overlay presents it as an `AinkradConfirmDialog`; the catalog that
    /// asked has been rebuilt by then, so the request lives here.
    var pendingConfirm: SettingsConfirmRequest?
    /// Theme files' modal (the load issues) is open.
    var showsThemeFiles = false
    /// The one shortcut recorder the Keyboard rows share. Stopped when the
    /// settings overlay closes, so a key pressed later never rebinds anything.
    let recorder = ShortcutRecorder()

    func speech(_ persistence: PersistenceStore) -> SpeechSynthesisSettingsStore {
        if let speechStore { return speechStore }
        let made = SpeechSynthesisSettingsStore(persistence: persistence)
        speechStore = made
        return made
    }

    /// Forget the per-provider speech drafts, so switching provider shows that
    /// provider's saved values.
    func resetSpeechDrafts() {
        speechAPIKey = nil
        speechVoice = nil
        speechModel = nil
        speechBaseURL = nil
    }
}

/// A confirm the settings overlay shows for a destructive declared action.
/// `onConfirm` runs only when the user confirms.
struct SettingsConfirmRequest {
    let title: String
    let message: String
    let action: String
    let onConfirm: () -> Void
}

/// Drives the shared `NSColorPanel` for one declared color row at a time.
@MainActor
final class SettingsColorPanel: NSObject {
    static let shared = SettingsColorPanel()
    private var onChange: ((Color) -> Void)?

    func edit(_ color: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(color)
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.orderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))  // design-lint: allow raw-color kit gap, declared color row
    }
}
