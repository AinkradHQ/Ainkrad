import Testing
import SwiftUI
@testable import Ainkrad
import AinkradAppKitContract

/// Pins the Task 7 decomposition — as it stands AFTER review.
///
/// SCOPE NOTE — this asserts over the **Voice group only**, narrowed twice, both
/// times deliberately:
///
///  1. `Speech` (`TTSSettingsView`) was never in this task's scope, so a
///     whole-page "no `.custom`" assertion could never have passed.
///  2. `Sound` was decomposed once and **reverted after the review gate**: one
///     field per control made each of the 13 `UISound` events three rows with
///     near-duplicate labels. It is declared again (Enhancements E7) the way
///     that review asked for — ONE row per cue, a menu of "Off" or the effect,
///     which previews on choosing. `soundIsOneRowPerCue` pins that shape.
///
/// The push-to-talk chord is a read-only `.shortcut` row (it is changed under
/// Keyboard), so it carries no default or reset of its own.
@Suite("Sound & Voice fields")
@MainActor
struct SettingsSoundVoiceFieldsTests {
    private var page: SettingsPage {
        HostSettingsCatalog.build(environment: .preview())
            .pages(in: .workspace).first { $0.title == "Sound & Voice" }!
    }

    private var voiceGroup: SettingsGroup? {
        page.groups.first { $0.title == "Voice" }
    }

    private var voiceFields: [SettingsField] { voiceGroup?.fields ?? [] }

    @Test("the page carries Sound, Voice and Speech groups")
    func groupsExist() {
        let titles = page.groups.map(\.title)
        #expect(titles.contains("Sound"))
        #expect(titles.contains("Voice"))
        #expect(titles.contains("Speech"))
    }

    @Test("the Voice group is declarative — no .custom at all")
    func noCustomFields() {
        for field in voiceFields {
            if case .custom = field.kind {
                Issue.record("\(field.path) is still .custom after decomposition")
            }
        }
    }

    /// Value-bearing fields only. `.action` and `.custom` carry no value, so
    /// `SettingsField` documents `reset == nil` as "no meaningful reset" — a
    /// no-op reset closure just to satisfy a test would be a lie, and would
    /// paint a revert arrow on a row that has nothing to revert.
    private var valueFields: [SettingsField] {
        voiceFields.filter {
            switch $0.kind {
            case .action, .custom, .shortcut: return false
            default: return true
            }
        }
    }

    @Test("every value field carries a default, a modified check, and a reset")
    func fieldsAreResettable() {
        for field in valueFields {
            #expect(field.defaultDescription != nil, "\(field.path) has no declared default")
            #expect(field.reset != nil, "\(field.path) cannot be reset")
        }
    }

    @Test("every field carries keywords so search finds it by synonym")
    func fieldsHaveKeywords() {
        for field in voiceFields {
            #expect(!field.keywords.isEmpty, "\(field.path) has no keywords")
        }
    }

    @Test("a toggle round-trips through its real store")
    func toggleRoundTrips() throws {
        let field = try #require(voiceFields.first {
            if case .toggle = $0.kind { return true }
            return false
        })
        guard case .toggle(let binding) = field.kind else { return }
        let original = binding.wrappedValue
        binding.wrappedValue = !original
        #expect(binding.wrappedValue == !original, "write did not reach the store")
        binding.wrappedValue = original
    }

    @Test("reset restores the declared default for every value field")
    func resetRestoresDefault() {
        for field in valueFields {
            field.reset?()
            let why = "\(field.path) still reads as modified after reset — its declared default "
                + "probably disagrees with the store's real default"
            #expect(field.isModified() == false, "\(why)")
        }
    }

    // MARK: - Nothing became unreachable

    /// Every control the voice pane exposed, including the chord display which
    /// is the one allowed `.custom`.
    @Test("every voice control survived the conversion")
    func voiceControlsSurvived() {
        let labels = Set(voiceFields.map(\.label))
        for expected in ["Backend", "Push-to-talk mode", "Auto-send after dictation",
                         "Upload audio to provider", "Connection", "Model", "Locale",
                         "Push-to-talk hotkey"] {
            #expect(labels.contains(expected), "\(expected) became unreachable")
        }
    }

    /// One row per cue — never the three near-duplicate rows the review gate
    /// rejected — plus the master toggle and volume, and no custom pane.
    @Test("Sound is declared as one row per cue")
    @MainActor
    func soundIsOneRowPerCue() throws {
        let environment = AppEnvironment.preview()
        environment.generalSettingsStore.setSoundEnabled(true)
        let page = try #require(HostSettingsCatalog.build(environment: environment).pages
            .first { $0.path == SettingsPath(["workspace", "soundAndVoice"]) })
        let sound = try #require(page.groups.first { $0.title == "Sound" })
        #expect(sound.fields.count == 2 + UISound.allCases.count)
        #expect(Array(sound.fields.map(\.label).prefix(2)) == ["Sound effects", "Volume"])
        let cueLabels = sound.fields.dropFirst(2).map(\.label)
        #expect(Set(cueLabels).count == cueLabels.count, "two cue rows share a label")
        #expect(!sound.fields.contains { if case .custom = $0.kind { true } else { false } })
    }

    // MARK: - Defaults were read from the store, not inferred from labels

    /// Both of these read as affirmative but default to `false` in
    /// `VoiceSettingsDocument`. Pass 1 shipped "On" for one of them.
    @Test("affirmative-sounding voice toggles declare their real Off default")
    func affirmativeTogglesDefaultOff() {
        for label in ["Auto-send after dictation", "Upload audio to provider"] {
            let field = voiceFields.first { $0.label == label }
            #expect(field?.defaultDescription == "Off",
                    "\(label) must declare Off — the store default is false")
        }
    }

    /// A model NAME is not a credential; marking it `.secure` would hide it
    /// from search for no security benefit.
    @Test("the voice text fields are .text — neither holds a credential")
    func voiceTextFieldsAreNotSecure() {
        for label in ["Model", "Locale"] {
            let field = voiceFields.first { $0.label == label }
            if case .text = field?.kind {} else {
                Issue.record("\(label) should be .text")
            }
        }
    }
}
