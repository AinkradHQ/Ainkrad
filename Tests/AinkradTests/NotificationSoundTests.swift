import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

private final class FakePlayback: AudioPlayback {
    var volume: Float = 1.0
    var currentTime: TimeInterval = 0
    private(set) var playCallCount = 0
    func play() -> Bool { playCallCount += 1; return true }
}

@MainActor
@Suite("Notification sound")
struct NotificationSoundTests {
    @Test("a failure still chimes when interface sounds are switched off")
    func chromeSilenceDoesNotSilenceNotifications() {
        // The whole point: the General → Sound master governs interface chrome.
        // It is not consulted here, so turning off button clicks cannot also
        // turn off the alert that a build failed.
        let store = NotificationSoundStore(settings: .init(isEnabled: true, volume: 0.8))
        let token = FakePlayback()
        SoundEngine(settings: store, players: [.error: token]).play(.error)
        #expect(token.playCallCount == 1)
    }

    @Test("the notification switch is what silences notifications")
    func notificationSwitchSilences() {
        let store = NotificationSoundStore(settings: .init(isEnabled: false, volume: 0.8))
        let token = FakePlayback()
        SoundEngine(settings: store, players: [.error: token]).play(.error)
        #expect(token.playCallCount == 0)
    }

    @Test("notification volume is its own, not the interface volume")
    func volumeIsIndependent() {
        let store = NotificationSoundStore(settings: .init(isEnabled: true, volume: 0.25))
        let token = FakePlayback()
        SoundEngine(settings: store, players: [.error: token]).play(.error)
        #expect(token.volume == 0.25)
    }

    @Test("changing the setting takes effect on the very next sound")
    func changesApplyImmediately() {
        let store = NotificationSoundStore(settings: .init(isEnabled: true, volume: 0.8))
        let token = FakePlayback()
        let engine = SoundEngine(settings: store, players: [.error: token])
        engine.play(.error)
        store.settings.isEnabled = false
        engine.play(.error)
        #expect(token.playCallCount == 1)
    }

    @Test("a change notifies its owner so it can be persisted")
    func changesAreObservable() {
        var saved: NotificationSoundSettings?
        let store = NotificationSoundStore(settings: .init())
        store.onChange = { saved = $0 }
        store.settings.volume = 0.4
        #expect(saved?.volume == 0.4)
    }

    @Test("preferences written before notification sound existed still load")
    func decodesPreSoundPreferences() throws {
        var object = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SignalPreferences())) as? [String: Any])
        #expect(object.removeValue(forKey: "sound") != nil,
                "the field must be present today, or this test proves nothing")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let prefs = try JSONDecoder().decode(SignalPreferences.self, from: legacy)
        #expect(prefs.sound.isEnabled, "absent must mean on, not off")
    }
}
