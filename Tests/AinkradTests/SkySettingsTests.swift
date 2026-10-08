import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("SkyEffect catalog")
struct SkyEffectTests {
    @Test("every effect has a stable key, a name, and a description")
    func catalogWellFormed() {
        for effect in SkyEffect.allCases {
            #expect(!effect.rawValue.isEmpty)
            #expect(!effect.displayName.isEmpty)
            #expect(!effect.effectDescription.isEmpty)
        }
        #expect(Set(SkyEffect.allCases.map(\.rawValue)).count == SkyEffect.allCases.count)
    }
}

@Suite("GlobalSettings sky fields")
struct GlobalSettingsSkyTests {
    @Test("defaults: animated, normal speed, every effect enabled")
    func defaults() {
        let settings = GlobalSettings()
        #expect(settings.skyMotionEnabled)
        #expect(settings.skyMotionSpeed == 1.0)
        #expect(settings.skyEffectEnabled.isEmpty)
    }

    @Test("a legacy payload without sky fields decodes to the animated defaults")
    func legacyPayloadDecodes() throws {
        let legacy = Data(#"{"theme":"cyberPurple"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.skyMotionEnabled)
        #expect(decoded.skyMotionSpeed == 1.0)
        #expect(decoded.skyEffectEnabled.isEmpty)
    }

    @Test("sky fields round-trip through the persistence store")
    func roundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.skyMotionEnabled = false
        settings.skyMotionSpeed = 1.5
        settings.skyEffectEnabled = [SkyEffect.aurora.rawValue: false]
        store.save(settings)
        let loaded = store.load(GlobalSettings.self)
        #expect(loaded?.skyMotionEnabled == false)
        #expect(loaded?.skyMotionSpeed == 1.5)
        #expect(loaded?.skyEffectEnabled[SkyEffect.aurora.rawValue] == false)
    }
}

@Suite("SkySettingsStore")
@MainActor
struct SkySettingsStoreTests {
    @Test("defaults: animated, normal speed, every effect enabled")
    func defaults() {
        let store = SkySettingsStore(persistence: InMemoryPersistenceStore())
        #expect(store.motionEnabled)
        #expect(store.motionSpeed == 1.0)
        for effect in SkyEffect.allCases {
            #expect(store.isEnabled(effect))
        }
    }

    @Test("disabling an effect persists as an explicit opt-out; re-enabling removes the key")
    func optOutStorage() {
        let persistence = InMemoryPersistenceStore()
        let store = SkySettingsStore(persistence: persistence)

        store.setEnabled(false, for: .fireflies)
        #expect(!store.isEnabled(.fireflies))
        var saved = persistence.load(GlobalSettings.self)
        #expect(saved?.skyEffectEnabled[SkyEffect.fireflies.rawValue] == false)

        store.setEnabled(true, for: .fireflies)
        #expect(store.isEnabled(.fireflies))
        saved = persistence.load(GlobalSettings.self)
        #expect(saved?.skyEffectEnabled[SkyEffect.fireflies.rawValue] == nil)
    }

    @Test("master switch and speed persist, and other settings survive untouched")
    func masterAndSpeedPersist() {
        let persistence = InMemoryPersistenceStore()
        var existing = GlobalSettings()
        existing.colorSchemeDark = "dracula"
        persistence.save(existing)

        let store = SkySettingsStore(persistence: persistence)
        store.setMotionEnabled(false)
        store.setMotionSpeed(1.5)

        let saved = persistence.load(GlobalSettings.self)
        #expect(saved?.skyMotionEnabled == false)
        #expect(saved?.skyMotionSpeed == 1.5)
        #expect(saved?.colorSchemeDark == "dracula")  // preserved, not clobbered

        // A fresh store sees the persisted state.
        let reloaded = SkySettingsStore(persistence: persistence)
        #expect(!reloaded.motionEnabled)
        #expect(reloaded.motionSpeed == 1.5)
    }

    @Test("speed is clamped to the supported 0.5…1.5 band")
    func speedClamped() {
        let store = SkySettingsStore(persistence: InMemoryPersistenceStore())
        store.setMotionSpeed(3.0)
        #expect(store.motionSpeed == 1.5)
        store.setMotionSpeed(0.1)
        #expect(store.motionSpeed == 0.5)
    }

    @Test("an out-of-band persisted speed is clamped at load, not trusted")
    func persistedSpeedClampedAtLoad() {
        let persistence = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.skyMotionSpeed = 50
        persistence.save(settings)
        #expect(SkySettingsStore(persistence: persistence).motionSpeed == 1.5)

        settings.skyMotionSpeed = -1
        persistence.save(settings)
        #expect(SkySettingsStore(persistence: persistence).motionSpeed == 0.5)
    }
}

@Suite("SkyClock")
@MainActor
struct SkyClockTests {

    @Test("first tick is zero and time advances by delta × speed")
    func advances() {
        let clock = SkyClock()
        #expect(clock.tick(real: 100, speed: 1.0) == 0)
        #expect(clock.tick(real: 110, speed: 1.0) == 10)
        #expect(clock.tick(real: 112, speed: 0.5) == 11)  // only the new delta is scaled
    }

    @Test("a speed change never teleports accumulated time")
    func noTeleport() {
        let clock = SkyClock()
        _ = clock.tick(real: 0, speed: 1.0)
        let before = clock.tick(real: 1000, speed: 1.0)
        let after = clock.tick(real: 1001, speed: 1.5)
        #expect(after - before == 1.5)  // not 1000 × 1.5
    }

    @Test("same-instant re-ticks are idempotent and backwards time is clamped")
    func monotonic() {
        let clock = SkyClock()
        _ = clock.tick(real: 5, speed: 1.0)
        let value = clock.tick(real: 8, speed: 1.0)
        #expect(clock.tick(real: 8, speed: 1.0) == value)
        #expect(clock.tick(real: 7, speed: 1.0) == value)  // never runs backward
    }

    @Test("reset returns the clock to the frozen arrangement's zero")
    func resets() {
        let clock = SkyClock()
        _ = clock.tick(real: 0, speed: 1.0)
        _ = clock.tick(real: 500, speed: 1.0)
        clock.reset()
        #expect(clock.tick(real: 900, speed: 1.0) == 0)  // resumes smoothly from zero
        #expect(clock.tick(real: 901, speed: 1.0) == 1)
    }
}
