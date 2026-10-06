import Foundation

/// The sky's rare events — meteor showers, comets, aurora surges — and the
/// ambient shooting stars. Split from `SkyMath.swift` for size; the same
/// pure, deterministic discipline applies.
extension SkyMath {
    // MARK: Sky moments

    private static let showerInterval = 200.0  // shooting-star bursts ~3x more frequent (every ~3.3 min)
    private static let cometInterval = 480.0
    private static let surgeInterval = 300.0
    private static let shootingDuration = 0.9

    /// A brief burst of 3–5 staggered, overlapping streaks. Empty outside
    /// its rare window.
    static func meteorShower(time: Double) -> [ShootingStar] {
        let cycleIndex = (time / showerInterval).rounded(.down)
        let gate = fract(sin(cycleIndex * 57.585 + 2.7) * 37164.219)
        guard gate < 0.8 else { return [] }
        let burstStart = cycleIndex * showerInterval + fract(gate * 13.7) * 500
        let count = 3 + Int(fract(gate * 5.3) * 3)  // 3…5
        var streaks: [ShootingStar] = []
        for k in 0..<count {
            // 0.9 s stagger with 1.2 s flights: streaks overlap, so the
            // burst reads as one continuous event.
            let local = time - burstStart - Double(k) * 0.9
            guard local >= 0, local <= 1.2 else { continue }
            let h = fract(sin(cycleIndex * 17.23 + Double(k) * 91.7) * 43758.5453)
            let progress = local / 1.2
            streaks.append(
                ShootingStar(
                    startX: 0.1 + fract(h * 17.77) * 0.8,
                    startY: 0.05 + fract(h * 31.13) * 0.3,
                    angle: (fract(h * 7.31) < 0.5 ? 1.0 : -1.0) * (0.30 + fract(h * 3.77) * 0.25),
                    progress: progress,
                    brightness: sin(progress * .pi)
                ))
        }
        return streaks
    }

    /// A slow, majestic crossing over ~8 s, rarer than the shower.
    static func comet(time: Double) -> ShootingStar? {
        let cycleIndex = (time / cometInterval).rounded(.down)
        let gate = fract(sin(cycleIndex * 73.156 + 1.9) * 28657.114)
        guard gate < 0.6 else { return nil }
        let local = time - cycleIndex * cometInterval - fract(gate * 23.3) * 400
        guard local >= 0, local <= 8 else { return nil }
        let progress = local / 8
        return ShootingStar(
            startX: 0.1 + fract(gate * 17.77) * 0.8,
            startY: 0.05 + fract(gate * 31.13) * 0.3,
            angle: (fract(gate * 7.31) < 0.5 ? 1.0 : -1.0) * (0.18 + fract(gate * 3.77) * 0.15),
            progress: progress,
            brightness: sin(progress * .pi)
        )
    }

    /// An occasional bloom of the aurora, 0…1 — the ribbons briefly breathe
    /// brighter, then settle.
    static func auroraSurge(time: Double) -> Double {
        let cycleIndex = (time / surgeInterval).rounded(.down)
        let gate = fract(sin(cycleIndex * 43.921 + 3.3) * 19349.663)
        guard gate < 0.7 else { return 0 }
        let local = time - cycleIndex * surgeInterval - fract(gate * 11.9) * 280
        guard local >= 0, local <= 12 else { return 0 }
        return sin(local / 12 * .pi)
    }

    // MARK: Shooting stars

    struct ShootingStar: Equatable {
        let startX: Double  // 0…1
        let startY: Double  // 0…0.35 — upper sky only
        let angle: Double  // radians; sign is the travel direction
        let progress: Double  // 0…1 along the flight
        let brightness: Double  // 0…1, eased in and out
    }

    /// The ambient streaks: two independent lanes, each firing in most of
    /// its ~13–19 s cycles at a hashed offset — so one is never far away,
    /// the rhythm never feels metronomic, and now and then two cross the
    /// sky together. Deterministic like everything else here.
    static func shootingStars(time: Double) -> [ShootingStar] {
        var streaks: [ShootingStar] = []
        for lane in 0..<2 {
            let interval = 13.0 + Double(lane) * 6
            let cycleIndex = (time / interval).rounded(.down)
            let gate = fract(sin(cycleIndex * 91.317 + 4.2 + Double(lane) * 37.7) * 24634.6345)
            guard gate < 0.6 else { continue }
            let offset = fract(gate * 9.1) * (interval - shootingDuration - 0.1)
            let local = time - cycleIndex * interval - offset
            guard local >= 0, local <= shootingDuration else { continue }
            let progress = local / shootingDuration
            let direction = fract(gate * 7.31) < 0.5 ? 1.0 : -1.0
            streaks.append(
                ShootingStar(
                    startX: 0.1 + fract(gate * 17.77) * 0.8,
                    startY: 0.05 + fract(gate * 31.13) * 0.3,
                    angle: direction * (0.30 + fract(gate * 3.77) * 0.25),
                    progress: progress,
                    brightness: sin(progress * .pi)
                ))
        }
        return streaks
    }
}
