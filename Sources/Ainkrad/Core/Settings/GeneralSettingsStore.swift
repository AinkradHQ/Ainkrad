import AppKit
import Observation
import AinkradHostRuntime

/// Owns the Settings → General section: the full-screen status bar toggle
/// (AIN-109) and the sound effects toggle/volume (AIN-108). Loads from
/// `GlobalSettings` and persists changes while preserving the rest of the
/// document — same load/mutate/save pattern as `AppIconStore`.
///
/// Conforms to `SoundSettingsProviding` so `SoundEngine` can read
/// enabled/volume directly off this store — no separate settings object.
@MainActor
@Observable
final class GeneralSettingsStore: SoundSettingsProviding {
    private(set) var showFullScreenStatusBar: Bool
    private(set) var soundEnabled: Bool
    private(set) var soundVolume: Double
    /// Per-event enable switches (missing key = enabled) and effect overrides
    /// (missing key = the event's own sound) — see `GlobalSettings`.
    private(set) var soundEventEnabled: [String: Bool]
    private(set) var soundEventEffects: [String: String]
    /// Overlay panel background opacity + blur (Settings → Appearance).
    private(set) var overlayBackgroundOpacity: Double
    private(set) var overlayBlurEnabled: Bool
    /// Launcher (⌘K) layout — list or grid (Settings → General).
    private(set) var launcherViewMode: LauncherViewMode
    /// AINKRAD-controlled motion preference (independent of the macOS
    /// system-level Reduce Motion toggle), injected into `\.ainkradReduceMotion`
    /// at the host root. Toggled in Settings → Appearance → Motion; default
    /// false = motion on.
    private(set) var uiReduceMotion: Bool
    /// Whether a relaunch reopens the apps that were tiled at quit
    /// (Settings → General → Workspace). Default false — see `GlobalSettings`.
    private(set) var restoreLayoutOnLaunch: Bool
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        // Motion is app-owned only: `uiReduceMotion` is controlled solely by the
        // in-app setting (Settings → Appearance → Motion), defaulting to motion
        // ON. The macOS system Reduce Motion flag is intentionally never read —
        // an accessibility user who wants the app's motion suppressed toggles it
        // here, and the OS setting can't silently disable it.
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.showFullScreenStatusBar = settings.showFullScreenStatusBar
        self.soundEnabled = settings.soundEnabled
        self.soundVolume = settings.soundVolume
        self.soundEventEnabled = settings.soundEventEnabled
        self.soundEventEffects = settings.soundEventEffects
        self.overlayBackgroundOpacity = settings.overlayBackgroundOpacity
        self.overlayBlurEnabled = settings.overlayBlurEnabled
        self.launcherViewMode = settings.launcherViewMode
        self.uiReduceMotion = settings.uiReduceMotion
        self.restoreLayoutOnLaunch = settings.restoreLayoutOnLaunch
    }

    func setRestoreLayoutOnLaunch(_ isOn: Bool) {
        restoreLayoutOnLaunch = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.restoreLayoutOnLaunch = isOn
        persistence.save(settings)
    }

    func setLauncherViewMode(_ mode: LauncherViewMode) {
        launcherViewMode = mode
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.launcherViewMode = mode
        persistence.save(settings)
    }

    func setOverlayBackgroundOpacity(_ value: Double) {
        let clamped = min(max(value, 0.3), 1.0)
        overlayBackgroundOpacity = clamped
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.overlayBackgroundOpacity = clamped
        persistence.save(settings)
    }

    func setOverlayBlurEnabled(_ isOn: Bool) {
        overlayBlurEnabled = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.overlayBlurEnabled = isOn
        persistence.save(settings)
    }

    func setUiReduceMotion(_ isOn: Bool) {
        uiReduceMotion = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.uiReduceMotion = isOn
        persistence.save(settings)
    }

    func setShowFullScreenStatusBar(_ isOn: Bool) {
        showFullScreenStatusBar = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.showFullScreenStatusBar = isOn
        persistence.save(settings)
    }

    func setSoundEnabled(_ isOn: Bool) {
        soundEnabled = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundEnabled = isOn
        persistence.save(settings)
    }

    func setSoundVolume(_ volume: Double) {
        soundVolume = volume
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundVolume = volume
        persistence.save(settings)
    }

    // MARK: Per-event control (Settings → General → Sound Effects)

    func isEventEnabled(_ event: UISound) -> Bool {
        soundEventEnabled[event.rawValue] ?? true
    }

    func effect(for event: UISound) -> UISound {
        guard let raw = soundEventEffects[event.rawValue],
              let chosen = UISound(rawValue: raw) else { return event }
        return chosen
    }

    func setEventEnabled(_ isOn: Bool, for event: UISound) {
        // Only explicit opt-outs are stored; enabling removes the key so the
        // persisted doc stays minimal and future events default to enabled.
        soundEventEnabled[event.rawValue] = isOn ? nil : false
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundEventEnabled = soundEventEnabled
        persistence.save(settings)
    }

    func setEffect(_ effect: UISound, for event: UISound) {
        // The event's own sound is the default; picking it removes the key.
        soundEventEffects[event.rawValue] = effect == event ? nil : effect.rawValue
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.soundEventEffects = soundEventEffects
        persistence.save(settings)
    }
}
