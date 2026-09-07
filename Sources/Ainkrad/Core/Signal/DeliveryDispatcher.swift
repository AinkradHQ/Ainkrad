import Foundation
import AinkradAppKit
import AinkradSignal

@MainActor protocol ToastPresenting: AnyObject {
    func present(_ event: SignalEvent)
}

/// Turns a routing decision into effects. Holds no policy of its own - if you
/// find yourself adding an `if` about *whether* to deliver, it belongs in
/// `route(_:rules:context:)` where it is testable as a table row.
@MainActor
final class DeliveryDispatcher: SignalDeliverer {
    private let banner: any BannerPosting
    private let toast: any ToastPresenting
    private let sound: any SoundPlaying
    private let badge: (SignalSource) -> Void

    init(banner: any BannerPosting,
         toast: any ToastPresenting,
         sound: any SoundPlaying,
         badge: @escaping (SignalSource) -> Void) {
        self.banner = banner
        self.toast = toast
        self.sound = sound
        self.badge = badge
    }

    /// Live routing rules, so cue selection can read a per-source choice. Set
    /// by the bootstrap; without it the severity table applies, which is the
    /// same answer an unconfigured source would get anyway.
    var rules: () -> RoutingRules = { .default }
    private var burstGate = SignalBurstGate()

    func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
        // `.feed` needs no work here: SignalCenter persisted the event before
        // routing, so the feed is already correct.
        if channels.contains(.banner) { banner.post(event) }
        if channels.contains(.toast) { toast.present(event) }
        if channels.contains(.sound) { playSound(for: event) }
        if channels.contains(.badge) { badge(event.source) }
    }

    /// Cue choice is policy and lives in `SignalCue`; this only decides
    /// whether a burst has already been heard.
    private func playSound(for event: SignalEvent) {
        guard let cue = SignalCue.cue(for: event, rules: rules()) else { return }
        guard burstGate.admits(Date(), rank: SignalCue.rank(event.severity)) else { return }
        sound.play(cue)
    }
}

/// The kit's `SignalToastModel` deliberately conforms to nothing — it must not
/// know the host's delivery seam exists. `present(_:)` already matches, so the
/// conformance is added here, where that seam is defined.
extension SignalToastModel: ToastPresenting {}
