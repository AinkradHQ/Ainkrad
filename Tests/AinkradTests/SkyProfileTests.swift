import AinkradHostRuntime
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("Sky profile — per-theme character")
@MainActor
struct SkyProfileTests {
    @Test("the neutral profile leaves every effect at its baseline")
    func neutralIsUnity() {
        let neutral = SkyProfile.neutral
        #expect(neutral.aurora == 1)
        #expect(neutral.embers == 1)
        #expect(neutral.mist == 1)
        #expect(neutral.fireflies == 1)
        #expect(neutral.lightRays == 1)
    }

    @Test("every theme exposes a sky profile with positive emphasis")
    func everyThemeHasAPositiveProfile() {
        for theme in neonSchemeIDs {
            let profile = NeonSchemes.host(theme).skyProfile
            #expect(profile.aurora > 0)
            #expect(profile.embers > 0)
            #expect(profile.mist > 0)
            #expect(profile.fireflies > 0)
            #expect(profile.lightRays > 0)
        }
    }

    @Test("profiles are not all identical — themes must read differently")
    func profilesDiffer() {
        let profiles = Set(neonSchemeIDs.map { NeonSchemes.host($0).skyProfile })
        #expect(profiles.count > 1)
    }

    @Test("Gruvbox is ember-forward while Nord is misty and subdued")
    func characterMatchesIntent() {
        let gruvbox = NeonSchemes.host("gruvbox").skyProfile
        let nord = NeonSchemes.host("nord").skyProfile
        // Gruvbox: warm sunset — embers dominate over its aurora.
        #expect(gruvbox.embers > gruvbox.aurora)
        // Nord: cool and calm — mist dominates, embers pulled back.
        #expect(nord.mist > nord.embers)
        // Relative: Gruvbox's embers out-glow Nord's.
        #expect(gruvbox.embers > nord.embers)
    }
}
