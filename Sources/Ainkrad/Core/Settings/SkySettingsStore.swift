import AinkradHostRuntime
import Observation

/// Every live effect of the ambient sky, each individually switchable in
/// Settings → Living Sky. Raw values are the persistence keys — stable
/// across renames of the display strings.
enum SkyEffect: String, CaseIterable, Identifiable {
    case stars
    case aurora
    case embers
    case shootingStars
    case skyMoments
    case breathingSky
    case horizonMist
    case lightRays
    case fireflies
    case bokeh
    case weather
    case skyTraffic
    case celestial
    case constellations

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stars: return "Drifting stars"
        case .aurora: return "Aurora ribbons"
        case .embers: return "Rising embers"
        case .shootingStars: return "Shooting stars"
        case .skyMoments: return "Rare sky moments"
        case .breathingSky: return "Breathing sky"
        case .horizonMist: return "Horizon mist"
        case .lightRays: return "Light rays"
        case .fireflies: return "Island fireflies"
        case .bokeh: return "Foreground bokeh"
        case .weather: return "Sky moods"
        case .skyTraffic: return "Sky traffic"
        case .celestial: return "Moon & day cycle"
        case .constellations: return "Constellations"
        }
    }

    var effectDescription: String {
        switch self {
        case .stars: return "A starfield in slow, endless drift — twinkling, with occasional glints."
        case .aurora: return "Two soft ribbons of accent light shimmering high in the sky."
        case .embers: return "Tiny sparks rising gently from below."
        case .shootingStars:
            return "Brief streaks across the upper sky, every ten seconds or so — sometimes two together."
        case .skyMoments: return "Rare events: meteor-shower bursts, a slow comet, aurora surges."
        case .breathingSky: return "The horizon glow slowly swells and relaxes, like the sky inhaling."
        case .horizonMist: return "Faint fog bands sliding sideways near the horizon."
        case .lightRays: return "Soft god-rays fanning up from the sun below the horizon."
        case .fireflies: return "Energy motes drifting upward around the island."
        case .bokeh: return "A few large, out-of-focus orbs floating in the extreme foreground."
        case .weather: return "Slow atmosphere moods — clear spells sharpen the stars, hazy spells thicken the mist."
        case .skyTraffic: return "Every few minutes a distant vessel crosses the high sky, beacon blinking."
        case .celestial: return "A moon that arcs through the real night, and a horizon that warms at dawn and dusk."
        case .constellations: return "Rarely, neighboring stars brighten and faint lines trace between them."
        }
    }
}

/// Owns Settings → Living Sky: the master animate switch, the motion speed,
/// and the per-effect switches. Loads from `GlobalSettings` and persists
/// changes while preserving the rest of the document — same load/mutate/save
/// pattern as `GeneralSettingsStore`.
@MainActor
@Observable
final class SkySettingsStore {
    /// The supported animation-speed band.
    static let speedRange = 0.5...1.5

    /// The named speeds every surface offers. The store accepts the whole
    /// `speedRange`, but users are only ever shown these three.
    ///
    /// Defined ONCE, here, because two surfaces render it: Settings → Living
    /// Sky and the first-run Motion & Sound step. They had diverged — the
    /// wizard shipped a continuous slider where Settings had this picker, so
    /// the same setting looked like two different settings depending on where
    /// you met it. Every value is inside `speedRange`, so `setMotionSpeed`
    /// never has anything to clamp when the input comes from here.
    static let speedPresets: [(title: String, value: Double)] = [
        ("Calm", 0.6), ("Normal", 1.0), ("Lively", 1.5),
    ]

    /// The preset the current speed reads as, or the raw value when a
    /// hand-edited document sits between two presets — a picker must not claim
    /// a selection the store does not actually hold.
    static func nearestPreset(to speed: Double) -> Double {
        speedPresets.first { abs(speed - $0.value) < 0.01 }?.value ?? speed
    }

    /// The label for a preset value, empty for anything that is not one.
    static func presetTitle(_ value: Double) -> String {
        speedPresets.first { $0.value == value }?.title ?? ""
    }

    private(set) var motionEnabled: Bool
    private(set) var motionSpeed: Double
    /// Per-effect switches (missing key = enabled) — only explicit opt-outs
    /// are stored, so legacy docs and future effects need no migration.
    private(set) var effectEnabled: [String: Bool]
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.motionEnabled = settings.skyMotionEnabled
        // Clamp at the load boundary too — a hand-edited or future-build
        // payload must not drive the sky clock out of the supported band.
        self.motionSpeed = min(
            max(settings.skyMotionSpeed, Self.speedRange.lowerBound),
            Self.speedRange.upperBound
        )
        self.effectEnabled = settings.skyEffectEnabled
    }

    func isEnabled(_ effect: SkyEffect) -> Bool {
        effectEnabled[effect.rawValue] ?? true
    }

    func setEnabled(_ isOn: Bool, for effect: SkyEffect) {
        // Only explicit opt-outs are stored; enabling removes the key so the
        // persisted doc stays minimal.
        effectEnabled[effect.rawValue] = isOn ? nil : false
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.skyEffectEnabled = effectEnabled
        persistence.save(settings)
    }

    func setMotionEnabled(_ isOn: Bool) {
        motionEnabled = isOn
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.skyMotionEnabled = isOn
        persistence.save(settings)
    }

    func setMotionSpeed(_ speed: Double) {
        let clamped = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        motionSpeed = clamped
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.skyMotionSpeed = clamped
        persistence.save(settings)
    }
}
