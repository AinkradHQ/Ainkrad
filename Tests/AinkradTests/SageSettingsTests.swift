import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

// `SageSettingsTabTests` lived here. The Sage's pill bar is gone —
// its sections are top-level INTELLIGENCE pages now — so the partition
// invariant it guarded is replaced by `SettingsIATests`.

@Suite("App appearance font override")
@MainActor
struct AppAppearanceFontTests {
    private func store() -> AppAppearanceStore {
        AppAppearanceStore(persistence: InMemoryPersistenceStore())
    }
    @Test("font family/scale default to nil (inherit global)") func defaultsNil() {
        let s = store()
        #expect(s.fontFamily("sage") == nil)
        #expect(s.fontScale("sage") == nil)
    }
    @Test("set and read back a font family override") func familyRoundTrip() {
        let s = store()
        s.setFontFamily("sage", .jetBrainsMono)
        #expect(s.fontFamily("sage") == .jetBrainsMono)
    }
    @Test("set and read back a font scale override") func scaleRoundTrip() {
        let s = store()
        s.setFontScale("sage", .large)
        #expect(s.fontScale("sage") == .large)
    }
    @Test("clearing back to nil restores inherit") func clears() {
        let s = store()
        s.setFontFamily("sage", .system)
        s.setFontFamily("sage", nil)
        #expect(s.fontFamily("sage") == nil)
    }
    @Test("font override is independent of opacity/blur on the same entry") func independent() {
        let s = store()
        s.setSurfaceOpacity("sage", 0.5)
        s.setFontScale("sage", .small)
        #expect(s.surfaceOpacity("sage") == 0.5)
        #expect(s.fontScale("sage") == .small)
    }
}

@Suite("Sage typography resolver")
struct SageTypographyTests {
    @Test("nil override inherits global family and scale") func inherits() {
        let t = SageTypography.resolve(
            family: nil, scale: nil,
            globalFamily: .exo2, globalScale: .medium)
        #expect(t.family == .exo2)
        #expect(t.scale == UIFontScale.medium.multiplier)
    }
    @Test("override wins over global") func overrides() {
        let t = SageTypography.resolve(
            family: .jetBrainsMono, scale: .large,
            globalFamily: .exo2, globalScale: .small)
        #expect(t.family == .jetBrainsMono)
        #expect(t.scale == UIFontScale.large.multiplier)
    }
    @Test("partial override: family only, scale inherits") func partial() {
        let t = SageTypography.resolve(
            family: .system, scale: nil,
            globalFamily: .exo2, globalScale: .large)
        #expect(t.family == .system)
        #expect(t.scale == UIFontScale.large.multiplier)
    }
}
