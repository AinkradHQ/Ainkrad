import AVFoundation

/// The seam callers use to play UI sounds — lets views/stores trigger sound
/// without knowing about `AVAudioPlayer` or the enabled/volume settings.
@MainActor
protocol SoundPlaying {
    func play(_ sound: UISound)
    /// Plays an effect asset directly for the Settings per-sound preview —
    /// honors the master switch + volume but bypasses the per-event enable
    /// gate, so a disabled event's candidate effect is still auditionable.
    func preview(_ effect: UISound)
}

/// The subset of `GeneralSettingsStore` `SoundEngine` needs to decide
/// whether/how loud to play — lets tests substitute a fake without spinning
/// up real persistence, and lets `SoundEngine` read live settings changes
/// (muting takes effect on the very next `play` call).
@MainActor
protocol SoundSettingsProviding {
    var soundEnabled: Bool { get }
    var soundVolume: Double { get }
    /// Whether this specific event's cue plays (on top of the master
    /// `soundEnabled` switch). Defaults to `true` for conformers that don't
    /// track per-event state.
    func isEventEnabled(_ event: UISound) -> Bool
    /// The effect asset to play for this event — lets the user re-map, e.g.,
    /// Focus Mode to the `confirm` chime. Defaults to the event's own sound.
    func effect(for event: UISound) -> UISound
}

extension SoundSettingsProviding {
    func isEventEnabled(_ event: UISound) -> Bool { true }
    func effect(for event: UISound) -> UISound { event }
}

/// A thin seam over `AVAudioPlayer` so the enabled/volume gate in
/// `SoundEngine` is unit-testable without touching real audio playback —
/// `AVAudioPlayer` already has matching members, so the conformance below is
/// free.
@MainActor
protocol AudioPlayback: AnyObject {
    var volume: Float { get set }
    var currentTime: TimeInterval { get set }
    @discardableResult func play() -> Bool
}

extension AVAudioPlayer: AudioPlayback {}

/// Preloads one `AVAudioPlayer` per `UISound` — from a user-data override
/// directory when present (AIN-108 follow-up: lets a user swap in their own,
/// possibly copyrighted, sound pack outside the repo/bundle), else from the
/// app bundle — and plays them on demand, gated by `settings.soundEnabled`
/// and scaled by `settings.soundVolume`. A sound whose asset failed to load
/// (headless/CI, a bundle that doesn't ship `Resources/Sounds/`, or a
/// missing override) is silently skipped — playback is best-effort and must
/// never crash the app.
@MainActor
final class SoundEngine: SoundPlaying {
    private let settings: SoundSettingsProviding
    private var players: [UISound: AudioPlayback]
    /// Lazy-load inputs. `nil` when players were INJECTED (the test entry
    /// point) — in that mode nothing is ever loaded from disk or bundle, so a
    /// sound absent from the injected dictionary stays absent, exactly as
    /// before.
    private let bundle: Bundle?
    private let overrideDirectory: URL?

    /// Testing seam: how many players have been lazily loaded (or injected)
    /// so far. Used to assert production init touches nothing up front.
    var loadedPlayerCountForTesting: Int { players.count }

    /// Production entry point. Loads nothing. Players are created on first
    /// use, per sound, by `player(for:)`.
    ///
    /// WHY: this initialiser used to build an `AVAudioPlayer` for all 24
    /// `UISound` cases and `prepareToPlay()` each one — 261 ms, measured, on
    /// the launch critical path, and paid TWICE because the app constructs
    /// two engines. Almost every one of those players is never used in a
    /// given session.
    ///
    /// `bundle` defaults to `.main` (the app bundle); `overrideDirectory`
    /// defaults to `nil` (always use the bundle) — callers that want
    /// overrides (see `AppEnvironment.bootstrap`) pass a real directory,
    /// which need not exist yet (resolution falls back to the bundle).
    init(settings: SoundSettingsProviding, bundle: Bundle = .main, overrideDirectory: URL? = nil) {
        self.settings = settings
        self.players = [:]
        self.bundle = bundle
        self.overrideDirectory = overrideDirectory
    }

    /// Returns the player for `sound`, loading and caching it on first use.
    /// `nil` when the asset is missing or players were injected without it —
    /// callers skip silently, exactly as before.
    private func player(for sound: UISound) -> AudioPlayback? {
        if let existing = players[sound] { return existing }
        guard let bundle else { return nil }
        guard let url = SoundEngine.resolvedURL(
                for: sound,
                overrideDirectory: overrideDirectory,
                bundle: bundle,
                fileExists: { FileManager.default.fileExists(atPath: $0.path) }
              ),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[sound] = player
        return player
    }

    /// Pure override-resolution rule, extracted so it's unit-testable without
    /// touching real disk/bundle state: prefers
    /// `overrideDirectory/<sound.resourceName>.wav` when `fileExists` reports
    /// it present, else falls back to `bundle`'s bundled copy of the same
    /// name, else `nil` (caller skips that sound rather than crashing).
    nonisolated static func resolvedURL(
        for sound: UISound,
        overrideDirectory: URL?,
        bundle: Bundle,
        fileExists: (URL) -> Bool
    ) -> URL? {
        if let overrideDirectory {
            let overrideURL = overrideDirectory.appendingPathComponent("\(sound.resourceName).wav")
            if fileExists(overrideURL) {
                return overrideURL
            }
        }
        return bundle.url(forResource: sound.resourceName, withExtension: "wav")
    }

    /// Test entry point: inject fake playback tokens directly, bypassing
    /// bundle/file loading entirely — this is what makes the enabled-gate
    /// unit-testable (see `SoundTests.swift`).
    init(settings: SoundSettingsProviding, players: [UISound: AudioPlayback]) {
        self.settings = settings
        self.players = players
        self.bundle = nil
        self.overrideDirectory = nil
    }

    func play(_ sound: UISound) {
        guard settings.soundEnabled else { return }
        guard settings.isEventEnabled(sound) else { return }
        // Per-event remap: the user may point this event at a different
        // effect asset (Settings → General → Sound Effects).
        guard let player = player(for: settings.effect(for: sound)) else { return }
        player.volume = Float(settings.soundVolume)
        player.currentTime = 0
        player.play()
    }

    /// Plays an effect asset directly, bypassing the per-event enable gate
    /// (but honoring the master switch + volume) — used by the Settings
    /// per-sound rows to preview a candidate effect even while its event is
    /// disabled.
    func preview(_ effect: UISound) {
        guard settings.soundEnabled else { return }
        guard let player = player(for: effect) else { return }
        player.volume = Float(settings.soundVolume)
        player.currentTime = 0
        player.play()
    }
}
