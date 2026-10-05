import CoreGraphics
import Foundation

/// One star of the ambient sky field. Every property is a pure function of
/// the star's index, so the field is identical on every launch and needs no
/// stored state.
struct SkyStar: Equatable {
    let x: Double  // 0…1 spawn position across the sky
    let y: Double  // 0…1 spawn position down the sky
    let radius: Double  // points
    let depth: Int  // 0 far … 2 near; drives size and drift speed
    let baseOpacity: Double
    let isAccent: Bool  // drawn in the theme accent instead of white
    let vx: Double  // drift velocity, normalized sky-widths per second
    let vy: Double  // drift velocity, normalized sky-heights per second
}

/// Pure, deterministic motion math for the ambient sky — endlessly drifting
/// stars, twinkle, glints, and the occasional shooting star. No wall-clock
/// or randomness inside: the same (index, time) always produces the same
/// result, mirroring the discipline of the other motion code.
enum SkyMath {
    static let starCount = 420

    /// Positive fractional part, used as the deterministic "hash" everywhere
    /// (also how drifting positions wrap across the sky's edges forever).
    private static func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }

    // MARK: Field

    static func star(index: Int) -> SkyStar {
        let seed = Double(index)
        let pick = index % 5  // 60% far, 20% mid, 20% near
        let depth = pick < 3 ? 0 : (pick == 3 ? 1 : 2)
        let unit = fract(seed * 53.9)
        let radius: Double
        let baseOpacity: Double
        let speed: Double
        switch depth {
        case 0:
            radius = 0.5 + unit * 0.4
            baseOpacity = 0.10 + unit * 0.16
            speed = 0.0020 + fract(seed * 5.171) * 0.0018  // ~3–6 px/s on a 1600 px sky
        case 1:
            radius = 0.9 + unit * 0.5
            baseOpacity = 0.18 + unit * 0.20
            speed = 0.0032 + fract(seed * 5.171) * 0.0026
        default:
            radius = 1.3 + unit * 0.7
            baseOpacity = 0.26 + unit * 0.22
            speed = 0.0048 + fract(seed * 5.171) * 0.0036
        }
        // Each star picks its own heading — the field scatters in every
        // direction instead of streaming like weather.
        let heading = fract(seed * 9.421 + 0.17) * 2 * .pi
        return SkyStar(
            x: fract(seed * 127.153),
            y: fract(seed * 311.7 + 0.37),
            radius: radius,
            depth: depth,
            baseOpacity: baseOpacity,
            isAccent: index % 11 == 0,
            vx: cos(heading) * speed,
            vy: sin(heading) * speed
        )
    }

    /// Where a star is at `time`: its endless straight drift plus a slight
    /// sinusoidal wander, wrapped into 0…1 so the field never runs out.
    static func position(index: Int, time: Double) -> CGPoint {
        let star = star(index: index)
        let seed = Double(index)
        let wanderPhase = fract(seed * 3.313) * 2 * .pi
        let wanderSpeed = 0.10 + fract(seed * 1.877) * 0.20  // rad/s
        let wander = 0.0035 * sin(time * wanderSpeed + wanderPhase)
        return CGPoint(
            x: fract(star.x + star.vx * time + wander),
            y: fract(star.y + star.vy * time - wander)
        )
    }

    // MARK: Per-frame brightness

    /// Slow brightness breathing, 0.35…1.0. Each star gets its own speed and
    /// phase so the field never pulses in lockstep.
    static func twinkle(index: Int, time: Double) -> Double {
        let seed = Double(index)
        let speed = 0.25 + fract(seed * 0.173) * 0.45  // 0.25–0.7 rad/s
        let phase = fract(seed * 2.399) * 2 * .pi
        return 0.35 + 0.65 * (0.5 + 0.5 * sin(time * speed + phase))
    }

    /// A brief extra sparkle, 0…1. Each star fires in roughly a quarter of
    /// its 9–17 s cycles for under a second — sparse enough to stay calm.
    static func glint(index: Int, time: Double) -> Double {
        let seed = Double(index)
        let cycle = 9.0 + fract(seed * 0.731) * 8.0
        let cycleIndex = (time / cycle).rounded(.down)
        let gate = fract(sin(cycleIndex * 12.9898 + seed * 78.233) * 43758.5453)
        guard gate < 0.25 else { return 0 }
        let offset = fract(gate * 39.425) * (cycle - 1.2)
        let local = time - cycleIndex * cycle - offset
        guard local >= 0, local <= 0.9 else { return 0 }
        return sin(local / 0.9 * .pi)
    }

    // MARK: Aurora

    static let auroraRibbons = 2
    static let auroraSegments = 9

    /// One soft light-blob of an aurora ribbon. A ribbon is a chain of these
    /// drawn as overlapping radial gradients; the traveling phase offsets
    /// below make brightness and undulation roll along the chain the way
    /// real aurora curtains shimmer.
    struct AuroraSegment: Equatable {
        let x: Double  // 0…1 across the sky
        let y: Double  // 0…0.5 — upper sky only
        let radiusX: Double  // normalized to sky width
        let radiusY: Double  // normalized to sky width; flat band shape
        let opacity: Double  // ≤ 0.14 — always subtle
    }

    static func auroraSegment(ribbon: Int, segment: Int, time: Double) -> AuroraSegment {
        let r = Double(ribbon)
        let s = Double(segment)
        let count = Double(auroraSegments)

        // Home position along the band, with a little per-segment jitter so
        // the chain doesn't read as evenly spaced beads.
        let homeX = 0.14 + (s + 0.5) / count * 0.72 + (fract(r * 3.17 + s * 0.613) - 0.5) * 0.05
        let bandY = ribbon == 0 ? 0.15 : 0.29

        // Slow undulation traveling along the ribbon, plus a whole-ribbon
        // sway — minutes-scale cycles, nothing hurried.
        let waveSpeed = 2 * .pi / (55.0 + r * 22)
        let undulation = 0.035 * sin(time * waveSpeed - s * 0.9 + r * 2.1)
        let swaySpeed = 2 * .pi / (80.0 + r * 30)
        let sway = 0.025 * sin(time * swaySpeed + r * 1.3 + s * 0.15)

        // Mid-chain blobs are biggest and brightest; the ends taper away.
        let edgeFade = sin(.pi * (s + 0.5) / count)
        let radiusX = 0.08 + edgeFade * 0.05 + fract(s * 1.931 + r * 0.77) * 0.02

        // Brightness wave rolling along the chain — dips but never to zero.
        let shimmerSpeed = 2 * .pi / (26.0 + r * 9)
        let shimmer = 0.45 + 0.55 * (0.5 + 0.5 * sin(time * shimmerSpeed - s * 0.8 + r * 4.2))
        let base = ribbon == 0 ? 0.075 : 0.055

        return AuroraSegment(
            x: homeX + sway,
            y: bandY + undulation,
            radiusX: radiusX,
            radiusY: radiusX * 0.32,
            opacity: base * edgeFade * shimmer
        )
    }

    // MARK: Atmosphere

    /// The sky's slow breath, 0…1 — a ~26 s swell modulated by a ~3.5 min
    /// drift so no two breaths are identical. Drives the horizon glow and
    /// accent haze intensity.
    static func breath(time: Double) -> Double {
        0.5 + 0.5 * sin(time * 2 * .pi / 26 + 0.6 * sin(time * 2 * .pi / 210))
    }

    static let mistBands = 3

    /// One horizon fog band: a very wide, flat gradient blob sliding
    /// endlessly sideways near the bottom of the sky.
    struct MistBand: Equatable {
        let x: Double  // 0…1, wraps
        let y: Double  // 0.7…1.0 — horizon region
        let radiusX: Double  // normalized to sky width
        let radiusY: Double
        let opacity: Double  // ≤ 0.07
    }

    static func mistBand(index: Int, time: Double) -> MistBand {
        let seed = Double(index)
        let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
        let speed = direction * (0.004 + fract(seed * 0.713) * 0.004)
        let radiusX = 0.28 + fract(seed * 1.317) * 0.14
        return MistBand(
            x: fract(seed * 127.153 + speed * time),
            y: 0.80 + seed * 0.06 + 0.008 * sin(time * 0.05 + seed * 2.3),
            radiusX: radiusX,
            radiusY: radiusX * 0.18,
            opacity: 0.035 + 0.015 * sin(time * 2 * .pi / 40 + seed * 2.0)
        )
    }

    static let lightRayCount = 3

    /// One god-ray fanning up from the below-horizon sun, swaying almost
    /// imperceptibly. Angles are radians from vertical.
    struct LightRay: Equatable {
        let angle: Double  // |angle| < 0.8
        let width: Double  // normalized to sky width
        let opacity: Double  // ≤ 0.08
    }

    static func lightRay(index: Int, time: Double) -> LightRay {
        let seed = Double(index)
        return LightRay(
            angle: (seed - 1) * 0.30 + 0.05 * sin(time * 2 * .pi / 95 + seed * 1.7),
            width: 0.07 + fract(seed * 0.61) * 0.03,
            opacity: 0.035 + 0.02 * sin(time * 2 * .pi / 33 + seed * 2.4)
        )
    }

    // MARK: Fireflies and bokeh

    static let fireflyCount = 66

    /// One energy mote rising through the island's region, pulsing, fading
    /// in at the bottom of its column and out at the top — no pops.
    struct Firefly: Equatable {
        let x: Double  // 0.25…0.75 — island zone
        let y: Double  // 0.18…0.82
        let radius: Double  // points
        let opacity: Double  // ≤ 0.7
    }

    static func firefly(index: Int, time: Double) -> Firefly {
        let seed = Double(index)
        let riseSpeed = 0.010 + fract(seed * 0.377) * 0.012
        let climb = fract(seed * 311.7 + riseSpeed * time)  // 0…1 up the column
        let sway = 0.018 * sin(time * (0.3 + fract(seed * 0.559) * 0.3) + seed * 2.1)
        let pulse = 0.32 + 0.22 * sin(time * (0.8 + fract(seed * 0.733) * 0.6) + seed * 1.3)
        return Firefly(
            x: 0.30 + fract(seed * 127.153) * 0.38 + sway,
            y: 0.78 - climb * 0.56,
            radius: 1.0 + fract(seed * 53.9) * 1.2,
            opacity: pulse * sin(.pi * climb)  // edge fade kills pops
        )
    }

    static let bokehCount = 4

    /// One large, ultra-faint out-of-focus orb in the extreme foreground,
    /// drifting slower than everything else — camera depth.
    struct BokehOrb: Equatable {
        let x: Double
        let y: Double
        let radius: Double  // normalized to sky width
        let opacity: Double  // ≤ 0.06
    }

    static func bokehOrb(index: Int, time: Double) -> BokehOrb {
        let seed = Double(index)
        let heading = fract(seed * 11.71 + 0.31) * 2 * .pi
        let speed = 0.0012 + fract(seed * 0.923) * 0.0016
        return BokehOrb(
            x: fract(seed * 127.153 + cos(heading) * speed * time),
            y: fract(seed * 311.7 + 0.53 + sin(heading) * speed * time),
            radius: 0.03 + fract(seed * 7.7) * 0.045,
            opacity: 0.03 + 0.015 * sin(time * 2 * .pi / 45 + seed * 2.9)
        )
    }

    // MARK: Weather moods

    /// The sky's slow mood, 0 (crystal clear) … 1 (hazy) — two incommensurate
    /// multi-minute waves, so the atmosphere keeps wandering between moods
    /// without ever repeating a schedule. Clear spells sharpen the stars and
    /// thin the mist; hazy spells do the opposite.
    static func weather(time: Double) -> Double {
        0.5 + 0.5 * sin(time * 2 * .pi / 420 + 1.3 * sin(time * 2 * .pi / 660))
    }

    // MARK: Sky traffic

    /// A distant vessel crossing far behind the island — a tiny glow with a
    /// blinking beacon, gone in twenty seconds.
    struct Vessel: Equatable {
        let y: Double  // 0.05…0.4 — high sky lane
        let direction: Double  // +1 left→right, −1 right→left
        let progress: Double  // 0…1 across the sky
        let brightness: Double  // 0…1, fades at both edges
    }

    static func vessel(time: Double) -> Vessel? {
        let interval = 150.0
        let duration = 20.0
        let cycleIndex = (time / interval).rounded(.down)
        let gate = fract(sin(cycleIndex * 67.219 + 5.1) * 31872.42)
        guard gate < 0.6 else { return nil }
        let offset = fract(gate * 13.3) * (interval - duration - 1)
        let local = time - cycleIndex * interval - offset
        guard local >= 0, local <= duration else { return nil }
        let progress = local / duration
        return Vessel(
            y: 0.08 + fract(gate * 29.7) * 0.28,
            direction: fract(gate * 7.7) < 0.5 ? 1 : -1,
            progress: progress,
            brightness: sin(progress * .pi)
        )
    }

    // MARK: Celestial (real time of day)

    /// The moon and the day's mood. Unlike everything else in this file,
    /// `dayFraction` is real local time (0 = midnight … 1 = next midnight) —
    /// deliberately, so the workspace at 2 AM doesn't look like noon. The
    /// function itself stays pure; the caller supplies the clock.
    struct Celestial: Equatable {
        let x: Double  // 0…1 across the sky (valid while bright)
        let y: Double  // upper sky arc
        let brightness: Double  // 0…1; 0 through the day
        let glowBoost: Double  // 0…0.35 extra horizon glow at dawn/dusk
    }

    static func celestial(dayFraction: Double) -> Celestial {
        let f = fract(dayFraction)
        // Night runs 19:00 → 07:00; progress 0…1 across it.
        let nightProgress: Double? =
            f >= 0.79 ? (f - 0.79) / 0.5 : f <= 0.29 ? (f + 0.21) / 0.5 : nil
        let brightness = nightProgress.map { sin(.pi * $0) } ?? 0
        // Dawn (~06:30) and dusk (~19:30) warm the horizon briefly.
        func bump(_ center: Double) -> Double {
            let d = (f - center) / 0.07
            return max(0, 1 - d * d)
        }
        return Celestial(
            x: nightProgress.map { 0.14 + $0 * 0.72 } ?? 0,
            y: nightProgress.map { 0.30 - 0.22 * sin(.pi * $0) } ?? 0,
            brightness: max(0, brightness),
            glowBoost: 0.3 * max(bump(0.27), bump(0.81))
        )
    }

    // MARK: Constellations

    /// A rare little secret: a handful of neighboring stars brighten and
    /// faint lines trace between them for a few seconds, then dissolve.
    struct Constellation: Equatable {
        let points: [CGPoint]  // normalized, upper sky
        let progress: Double  // 0…1 through the moment
        let brightness: Double  // 0…1, eased in and out
    }

    static func constellation(time: Double) -> Constellation? {
        let interval = 90.0
        let duration = 10.0
        let cycleIndex = (time / interval).rounded(.down)
        let gate = fract(sin(cycleIndex * 29.443 + 7.7) * 15731.77)
        guard gate < 0.5 else { return nil }
        let offset = fract(gate * 11.3) * (interval - duration - 1)
        let local = time - cycleIndex * interval - offset
        guard local >= 0, local <= duration else { return nil }

        let count = 4 + Int(fract(gate * 5.9) * 3)
        let anchorX = 0.12 + fract(gate * 17.7) * 0.76
        let anchorY = 0.06 + fract(gate * 31.3) * 0.30
        let points = (0..<count).map { member -> CGPoint in
            let m = Double(member)
            let dx = (fract(sin(cycleIndex * 13.7 + m * 97.3) * 43758.5453) - 0.5) * 0.18
            let dy = (fract(sin(cycleIndex * 17.9 + m * 61.7) * 27183.1) - 0.5) * 0.14
            return CGPoint(
                x: min(max(anchorX + dx, 0.02), 0.98),
                y: min(max(anchorY + dy, 0.02), 0.48)
            )
        }
        let progress = local / duration
        return Constellation(
            points: points,
            progress: progress,
            brightness: sin(progress * .pi)
        )
    }

    // MARK: Embers

    static let emberCount = 70

    /// One ember rising gently from below, twinkling. Positions are
    /// normalized so the field rescales smoothly with the window instead of
    /// scrambling when a pixel-space modulus changes.
    struct Ember: Equatable {
        let x: Double  // 0…1
        let y: Double  // 0…1, wraps as it rises
        let radius: Double  // points
        let opacity: Double  // ≤ 0.55
        let isAccent: Bool
    }

    static func ember(index: Int, time: Double) -> Ember {
        let seed = Double(index)
        let riseSpeed = 0.005 + fract(seed * 31.7) * 0.008  // sky-heights per second
        let twinkle = 0.5 + 0.5 * sin(time * (0.6 + fract(seed * 17.3)) + seed)
        let isAccent = index % 9 == 0
        return Ember(
            x: fract(seed * 127.153),
            y: fract(seed * 311.7 - riseSpeed * time),
            radius: 0.6 + fract(seed * 53.9) * 1.3,
            opacity: (isAccent ? 0.5 : 0.22) * twinkle,
            isAccent: isAccent
        )
    }

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
