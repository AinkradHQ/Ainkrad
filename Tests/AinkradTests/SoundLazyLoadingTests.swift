import Foundation
import Testing
@testable import Ainkrad

@Suite("SoundEngine lazy loading")
@MainActor
struct SoundLazyLoadingTests {
    @Test func productionInitLoadsNoPlayersUpFront() {
        // The whole point: constructing the engine must not touch the bundle.
        let engine = SoundEngine(settings: FakeSoundSettings())
        #expect(engine.loadedPlayerCountForTesting == 0)
    }

    @Test func injectedPlayersAreNeverLazilyLoaded() {
        // Injected mode must not fall through to bundle loading, or tests that
        // assert "a missing sound is skipped" would start finding real assets.
        let engine = SoundEngine(settings: FakeSoundSettings(), players: [:])
        engine.play(.confirm)
        #expect(engine.loadedPlayerCountForTesting == 0)
    }
}
