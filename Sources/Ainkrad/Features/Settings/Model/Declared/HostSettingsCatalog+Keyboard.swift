import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// Keyboard as DECLARED rows. A shortcut row's button shows its keys; clicking
/// it records the next combination (Esc cancels) through the same
/// `ShortcutRecorder` the old view used, so conflicts are refused the same way.
@MainActor
extension HostSettingsCatalog {
    static func keyboardGroups(_ environment: AppEnvironment, page: SettingsPath) -> [SettingsGroup] {
        let store = environment.shortcutStore
        let recorder = environment.settingsDrafts.recorder
        let group = page.appending("shortcuts")
        var fields = [
            SettingsField(
                path: group.appending("reset-all"), label: "Reset shortcuts",
                help: "Restore every shortcut to its default.",
                keywords: ["shortcuts", "reset", "defaults"],
                kind: .action(title: "Reset all") {
                    recorder.stop()
                    store.resetToDefaults()
                })
        ]
        fields += ShortcutAction.allCases.map { action in
            let recording = recorder.action == action
            return SettingsField(
                path: group.appending(action.rawValue), label: action.displayName,
                help: recording ? "Press a new combination. Esc cancels." : nil,
                keywords: ["hotkey", "binding", "key", "shortcut", action.displayName.lowercased()],
                kind: .action(title: recording ? "Press keys…" : store.chord(for: action).displayString) {
                    if recording { recorder.stop() } else { recorder.start(action, store: store) }
                },
                defaultDescription: action.defaultChord.displayString,
                isModified: { store.bindings.overrides[action.rawValue] != nil },
                reset: {
                    recorder.stop()
                    store.resetToDefault(action)
                })
        }
        let system = page.appending("system")
        return [
            SettingsGroup(
                path: group, title: "Shortcuts",
                footerNote: recorder.conflictMessage
                    ?? "Click a shortcut, then press a new key combination. Esc cancels.",
                fields: fields),
            SettingsGroup(
                path: system, title: "System",
                footerNote: "Fixed shortcuts for pane and workspace navigation — not customizable yet.",
                fields: systemShortcuts.map { name, chord in
                    SettingsField(
                        path: system.appending(name.lowercased().replacingOccurrences(of: " ", with: "-")),
                        label: name, keywords: ["shortcut", "navigation", name.lowercased()],
                        kind: .shortcut(.constant(chord)))
                }),
        ]
    }

    private static let systemShortcuts: [(String, String)] = [
        ("Pane Focus", "⌘←→↑↓"),
        ("Resize Pane", "⌘⇧←→↑↓"),
        ("Cycle Workspace", "⌘⌥←→"),
        ("Jump to Workspace", "⌘1–9"),
    ]
}
