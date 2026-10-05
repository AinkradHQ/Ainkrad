import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup motion and sound step")
@MainActor
struct SetupMotionSoundStepTests {
    @Test func choicesApplyImmediately() {
        let t = TestHome.make("motion")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupMotionSound.apply(
            reduceMotion: true, skyMotion: false, skySpeed: 0.8,
            soundEnabled: false, volume: 0.4,
            general: env.generalSettingsStore, sky: env.skySettingsStore)

        #expect(env.generalSettingsStore.uiReduceMotion)
        #expect(!env.skySettingsStore.motionEnabled)
        #expect(env.skySettingsStore.motionSpeed == 0.8)
        #expect(!env.generalSettingsStore.soundEnabled)
        #expect(env.generalSettingsStore.soundVolume == 0.4)
    }

    /// setMotionSpeed clamps to SkySettingsStore.speedRange (0.5...1.5).
    @Test func anOutOfRangeSpeedIsClamped() {
        let t = TestHome.make("motion2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupMotionSound.apply(
            reduceMotion: false, skyMotion: true, skySpeed: 9.0,
            soundEnabled: true, volume: 0.5,
            general: env.generalSettingsStore, sky: env.skySettingsStore)

        #expect(env.skySettingsStore.motionSpeed == 1.5)
    }

    /// The proof this step promises in its own copy: reduce-motion turned on
    /// here must stop the REMAINING steps animating immediately.
    ///
    /// The seam is store → `\.ainkradReduceMotion` (injected at the host root
    /// from `generalSettingsStore.uiReduceMotion`, which is `@Observable`) →
    /// `SetupStageMotion`. This asserts the two ends that are testable without
    /// a view host: the store reports the new value the instant it is set, and
    /// the stage's whole motion vocabulary collapses when handed it. Nothing is
    /// cached, and no relaunch is involved.
    @Test func reduceMotionTurnedOnHereCollapsesTheRestOfTheWizard() {
        let t = TestHome.make("motion3")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let store = env.generalSettingsStore

        // Set the starting state explicitly rather than leaning on the default:
        // what is under test is that the toggle takes effect immediately, and
        // seeding from the default would make this test silently change meaning
        // the next time the default moves — which it has, twice.
        store.setUiReduceMotion(false)
        #expect(!store.uiReduceMotion)
        #expect(
            SetupStageMotion.transition(reduceMotion: store.uiReduceMotion)
                == .layered(isForward: true))

        store.setUiReduceMotion(true)

        // Same run, same store instance — no reload, no relaunch.
        #expect(store.uiReduceMotion)
        #expect(SetupStageMotion.transition(reduceMotion: store.uiReduceMotion) == .none)
        #expect(SetupStageMotion.animation(reduceMotion: store.uiReduceMotion) == nil)
        for layer in SetupStageMotion.Layer.allCases {
            #expect(
                SetupStageMotion.layerGeometry(
                    layer,
                    reduceMotion: store.uiReduceMotion,
                    isForward: true) == nil)
            #expect(
                SetupStageMotion.layerGeometry(
                    layer,
                    reduceMotion: store.uiReduceMotion,
                    isForward: false) == nil)
        }

        // And it goes back, so Back to this step and switching it off is not a
        // one-way door either.
        store.setUiReduceMotion(false)
        #expect(SetupStageMotion.animation(reduceMotion: store.uiReduceMotion) != nil)
    }

    /// The wizard and Settings → Living Sky render the same speed control off
    /// the same presets. Pinned because they had diverged: a continuous slider
    /// here against a Calm/Normal/Lively picker there.
    @Test func theSpeedPresetsAreShared() {
        #expect(SkySettingsStore.speedPresets.map(\.title) == ["Calm", "Normal", "Lively"])
        for preset in SkySettingsStore.speedPresets {
            #expect(SkySettingsStore.speedRange.contains(preset.value))
            #expect(SkySettingsStore.nearestPreset(to: preset.value) == preset.value)
            #expect(SkySettingsStore.presetTitle(preset.value) == preset.title)
        }
    }

    /// A speed that is not a preset (a hand-edited document) must not be
    /// reported as one — the picker would then show a selection the store does
    /// not hold.
    @Test func aNonPresetSpeedIsReportedAsItself() {
        #expect(SkySettingsStore.nearestPreset(to: 0.83) == 0.83)
        #expect(SkySettingsStore.presetTitle(0.83) == "")
    }
}
