import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("DeliveryDispatcher")
final class DeliveryDispatcherTests {
    private final class SpyBanner: BannerPosting {
        var posted: [SignalEvent] = []
        func post(_ event: SignalEvent) { posted.append(event) }
    }
    private final class SpyToast: ToastPresenting {
        var shown: [SignalEvent] = []
        func present(_ event: SignalEvent) { shown.append(event) }
    }
    /// Conforms to the host's real sound seam, `SoundPlaying`.
    private final class SpySound: SoundPlaying {
        var played: [UISound] = []
        func play(_ sound: UISound) { played.append(sound) }
        func preview(_ effect: UISound) {}
    }

    private func event(_ severity: SignalSeverity = .info) -> SignalEvent {
        SignalEvent(source: .host, kind: "test.event", severity: severity, title: "t")
    }

    @Test("each channel reaches exactly its collaborator")
    func routesToCollaborators() {
        let banner = SpyBanner(); let toast = SpyToast(); let sound = SpySound()
        var badged: [SignalSource] = []
        let dispatcher = DeliveryDispatcher(banner: banner, toast: toast, sound: sound,
                                            badge: { badged.append($0) })
        dispatcher.deliver(event(), to: [.feed, .banner, .toast, .sound, .badge])
        #expect(banner.posted.count == 1)
        #expect(toast.shown.count == 1)
        #expect(sound.played == [.signalArrive])
        #expect(badged == [.host])
    }

    @Test("the feed channel alone touches nothing - the store already has it")
    func feedOnlyIsInert() {
        let banner = SpyBanner(); let toast = SpyToast(); let sound = SpySound()
        let dispatcher = DeliveryDispatcher(banner: banner, toast: toast, sound: sound, badge: { _ in })
        dispatcher.deliver(event(), to: [.feed])
        #expect(banner.posted.isEmpty)
        #expect(toast.shown.isEmpty)
        #expect(sound.played.isEmpty)
    }

    @Test("severity picks the sound")
    func soundBySeverity() {
        let sound = SpySound()
        let dispatcher = DeliveryDispatcher(banner: SpyBanner(), toast: SpyToast(),
                                            sound: sound, badge: { _ in })
        dispatcher.deliver(event(.failure), to: [.sound])
        dispatcher.deliver(event(.success), to: [.sound])
        // One sound, not two: the success lands inside the burst window and is
        // less severe than the failure just heard, so it is collapsed into it.
        #expect(sound.played == [.signalFail])
    }

    @Test("a failure is still heard when it follows chatter")
    func failureBreaksThroughABurst() {
        let sound = SpySound()
        let dispatcher = DeliveryDispatcher(banner: SpyBanner(), toast: SpyToast(),
                                            sound: sound, badge: { _ in })
        dispatcher.deliver(event(.info), to: [.sound])
        dispatcher.deliver(event(.failure), to: [.sound])
        // The direction that matters: burst suppression must never mute the
        // important event because an unimportant one arrived first.
        #expect(sound.played == [.signalArrive, .signalFail])
    }
}
