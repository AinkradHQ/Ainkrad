import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("GlobalSettings")
final class GlobalSettingsTests {
    @Test("defaults to Neon Blue with no prior write")
    func defaultsToNeonBlue() {
        let store = InMemoryPersistenceStore()
        let loaded = store.load(GlobalSettings.self) ?? GlobalSettings()
        #expect(loaded.theme == .neonBlue)
    }

    // Motion and sound are deliberately OPPOSITE defaults, which is the kind of
    // asymmetry a later edit "tidies up" into a single answer. Noise is opt-in;
    // movement is not. The wizard's opening screen is a moving composition, and
    // its Motion & Sound step is where either can be changed.
    //
    // Pinned because the polarity of `uiReduceMotion` inverts the reading —
    // motion ON is `false`.
    @Test("motion ships on, sound ships off")
    func motionOnAndSoundOffByDefault() {
        let fresh = GlobalSettings()
        #expect(fresh.uiReduceMotion == false, "uiReduceMotion false means motion PLAYS")
        #expect(fresh.soundEnabled == false)
        #expect(fresh.skyMotionEnabled == true)
    }

    // A settings file written before either key existed must answer the same way
    // a fresh install does. Splitting these two defaults is how one install
    // reports sound off in Settings while still playing sounds.
    @Test("a payload predating the motion and sound keys decodes to the same defaults")
    func decodeFallbacksAgreeWithTheDefaults() throws {
        let legacy = Data(#"{"theme":"neonBlue"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.uiReduceMotion == GlobalSettings().uiReduceMotion)
        #expect(decoded.soundEnabled == GlobalSettings().soundEnabled)
    }

    @Test("a written Cyber Purple selection round-trips through the persistence store")
    func cyberPurpleRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.theme = .cyberPurple
        store.save(settings)
        #expect(store.load(GlobalSettings.self)?.theme == .cyberPurple)
    }

    @Test("a legacy payload with an extra unknown field still decodes the theme")
    func legacyPayloadWithExtraFieldDecodes() throws {
        let legacy = Data(#"{"theme":"cyberPurple","appIcon":"purple"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .cyberPurple)
    }

    @Test("a payload without theme decodes to the Neon Blue default")
    func missingThemeDecodesToDefault() throws {
        let legacy = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .neonBlue)
    }

    @Test("defaults to medium/exo2/no accent override with no prior write")
    func typographyDefaults() {
        let settings = GlobalSettings()
        #expect(settings.uiFontScale == .medium)
        #expect(settings.uiFontFamily == .exo2)
        #expect(settings.accentColorHex == nil)
    }

    @Test("a written typography selection round-trips through the persistence store")
    func typographyRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.uiFontScale = .large
        settings.uiFontFamily = .jetBrainsMono
        settings.accentColorHex = "FF00AA"
        store.save(settings)

        let reloaded = store.load(GlobalSettings.self)
        #expect(reloaded?.uiFontScale == .large)
        #expect(reloaded?.uiFontFamily == .jetBrainsMono)
        #expect(reloaded?.accentColorHex == "FF00AA")
    }

    @Test("a legacy payload without the new typography keys decodes to defaults and preserves existing fields")
    func legacyPayloadWithoutTypographyKeysDecodesToDefaults() throws {
        let legacy = Data(#"{"theme":"cyberPurple","confirmBeforeQuit":false}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.theme == .cyberPurple)
        #expect(decoded.confirmBeforeQuit == false)
        #expect(decoded.uiFontScale == .medium)
        #expect(decoded.uiFontFamily == .exo2)
        #expect(decoded.accentColorHex == nil)
    }

    // The default itself is pinned by `motionAndSoundDefaultOff` above. What is
    // asserted here is that the STORE agrees with the model — a store that
    // seeded its own default would diverge from `GlobalSettings()` the moment
    // either one changed, which is exactly what happened when this default was
    // flipped.
    @MainActor
    @Test("a store with no prior write agrees with the model's default")
    func storeDefaultMatchesTheModel() {
        let persistence = InMemoryPersistenceStore()
        #expect(
            GeneralSettingsStore(persistence: persistence).uiReduceMotion
                == GlobalSettings().uiReduceMotion)
    }

    @MainActor
    @Test("setUiReduceMotion updates the store and persists across a fresh load")
    func reduceMotionSetterRoundTrips() {
        let persistence = InMemoryPersistenceStore()
        let store = GeneralSettingsStore(persistence: persistence)
        // Drive the setter AWAY from whatever the default is, so this test keeps
        // proving the setter works no matter which way the default is set.
        let opposite = !GlobalSettings().uiReduceMotion
        #expect(store.uiReduceMotion == !opposite)

        store.setUiReduceMotion(opposite)
        #expect(store.uiReduceMotion == opposite)
        // Persisted: a store rebuilt on the same backing sees the new value.
        #expect(GeneralSettingsStore(persistence: persistence).uiReduceMotion == opposite)
    }

    @MainActor
    @Test("first launch never adopts the macOS Reduce Motion flag")
    func reduceMotionNeverSeedsFromSystem() {
        let persistence = InMemoryPersistenceStore()
        // No prior document → the app's OWN default, regardless of the OS
        // setting; the app never reads the system Reduce Motion flag. The
        // in-app toggle is the sole source of truth.
        //
        // Compared against the model rather than a literal: with the app default
        // now `true`, a literal would pass just as readily if the store HAD
        // seeded itself from a system flag that happened to be on.
        #expect(
            GeneralSettingsStore(persistence: persistence).uiReduceMotion
                == GlobalSettings().uiReduceMotion)
    }
}
