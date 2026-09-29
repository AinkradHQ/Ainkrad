import SwiftUI
import AppKit
import AinkradHostRuntime

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

    func speech(_ persistence: PersistenceStore) -> SpeechSynthesisSettingsStore {
        if let speechStore { return speechStore }
        let made = SpeechSynthesisSettingsStore(persistence: persistence)
        speechStore = made
        return made
    }

    /// Forget the per-provider speech drafts, so switching provider shows that
    /// provider's saved values.
    func resetSpeechDrafts() {
        speechAPIKey = nil; speechVoice = nil; speechModel = nil; speechBaseURL = nil
    }
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
        onChange?(Color(nsColor: sender.color))
    }
}
