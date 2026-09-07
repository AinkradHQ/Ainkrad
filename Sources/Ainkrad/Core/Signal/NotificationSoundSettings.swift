import Foundation
import Observation

/// Whether notifications make a sound, and how loud.
///
/// Deliberately separate from General → Sound. That switch governs interface
/// chrome — pane opens, toggles, confirmations — and a user who turns those off
/// has said "stop clicking at me", not "stop telling me the build failed".
/// Routing them through the same gate meant the second thing happened silently
/// whenever the user asked for the first.
struct NotificationSoundSettings: Codable, Equatable {
    var isEnabled: Bool
    var volume: Double

    init(isEnabled: Bool = true, volume: Double = 0.7) {
        self.isEnabled = isEnabled
        self.volume = volume
    }

    /// Hand-written so a preferences file from before this existed decodes to
    /// sound ON. Absent must mean the previous behaviour, and the previous
    /// behaviour was audible — a migration that silences a user's alerts is
    /// indistinguishable from a bug, and they would never think to look here.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.7
    }
}

/// Holds the live notification sound settings and conforms to the sound
/// engine's settings seam, so a second `SoundEngine` can be built on top of it
/// with no changes to the engine at all.
///
/// A second engine rather than a bypass method on the first: the engine already
/// preloads one player per `UISound` and already implements the gate and the
/// volume scaling correctly. Reusing it with different settings is less code
/// than adding a parallel path through it, and it keeps the two volumes
/// genuinely independent instead of sharing one slider.
@MainActor
@Observable
final class NotificationSoundStore: SoundSettingsProviding {
    var settings: NotificationSoundSettings {
        didSet { if settings != oldValue { onChange?(settings) } }
    }

    /// Set by the bootstrap to persist the change.
    @ObservationIgnored var onChange: ((NotificationSoundSettings) -> Void)?

    init(settings: NotificationSoundSettings) { self.settings = settings }

    /// Which asset a cue actually plays, when the user has chosen one.
    ///
    /// Set by the bootstrap to read `GeneralSettingsStore`. A closure rather
    /// than a reference to that store, so this type keeps knowing nothing about
    /// settings plumbing and the mapping stays trivially testable.
    @ObservationIgnored var effectSource: ((UISound) -> UISound)?

    var soundEnabled: Bool { settings.isEnabled }
    var soundVolume: Double { settings.volume }

    /// `isEventEnabled` still takes the protocol's default. That is deliberate:
    /// General → Sound governs interface chrome, and letting it silence a
    /// failure alert is exactly the bug this type was split out to prevent.
    /// The notification pane stays the authority on WHETHER a cue plays.
    ///
    /// The EFFECT is a different question, and the old note here — "the
    /// notification cues are not in General → Sound's per-event list" — stopped
    /// being true. `SoundSettingsView` iterates `UISound.allCases`, so all five
    /// notification cues appear there with names like "Notification — Urgent".
    /// The user picked an effect, heard the ▶ preview play it, and then heard
    /// the default when a notification arrived, because this returned the
    /// protocol's identity default and never read the choice.
    func effect(for event: UISound) -> UISound { effectSource?(event) ?? event }
}
