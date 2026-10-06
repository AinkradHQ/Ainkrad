import CoreGraphics
import Foundation

// MARK: - Orbit field policy

/// The field of light around the mark: sparks travelling elliptical orbits, with
/// links drawn between any two that pass near each other.
///
/// Pure arithmetic, kept out of the view so the composition can be asserted at
/// times nobody will sit and watch. Every spark is generated from a fixed seed,
/// so the field is identical on every launch — a first-run screen that composes
/// differently each time cannot be art-directed.
///
/// This replaced a set of expanding rings. Rings enclosed the mark, which framed
/// it like a target; orbits travel past it on their own planes, and the depth
/// comes from each spark's size and brightness changing round its orbit. The
/// links are what make it read as a system of things working alongside each
/// other rather than as scattered dust.
///
/// The entire field renders BEHIND the mark — see `SetupBrandMark.composition`.
enum SetupOrbitField {
    struct Spark: Equatable {
        /// Orbit radius, as a fraction of the composition's width.
        let radius: CGFloat
        /// Rotation of the orbit's own plane. Different tilts are what stop the
        /// set from reading as a single flat ring.
        let tilt: Double
        /// How flat the ellipse is. Near 0 is edge-on, 1 is circular.
        let squash: CGFloat
        /// Radians per second, signed — some orbits run the other way.
        let speed: Double
        let phase: Double
        /// Base dot radius in points, at the composition's reference size.
        let size: CGFloat
    }

    /// The field is dense enough to read as a swarm rather than as a handful of
    /// countable dots — but it sits over a living, moving island behind the
    /// wizard's scrim, so brightness does the restraining instead of scarcity:
    /// most sparks spend most of their orbit dim and small.
    static let count = 32

    /// How near two sparks must be before a link is drawn, as a fraction of the
    /// composition's width.
    ///
    /// Tightened when the count went up: link opportunities grow with the SQUARE
    /// of the population, so holding this constant would have turned an
    /// occasional connection into a permanent mesh. Measured — at this value the
    /// field averages ~28 links at once; at the old 0.24 it was ~145.
    static let linkDistance: CGFloat = 0.10

    /// The reference width the `size` values are authored against, so a mark
    /// drawn at any diameter scales its sparks proportionally.
    static let referenceWidth: CGFloat = 300

    /// The instant the field is frozen at under reduce-motion.
    ///
    /// SEARCHED, not chosen by eye: the orbits have unrelated periods, so the
    /// composition at an arbitrary instant is arbitrary. This is the time in the
    /// first ten minutes whose WORST nearest-pair separation across a ±0.75s
    /// window is greatest — a plateau where the sparks are well spread, rather
    /// than a spike that a small change in the seed or the speeds would fall off.
    ///
    /// The measure is the gap between the closest pair's DRAWN EDGES — distance
    /// minus both radii — not between their centres, because two large sparks
    /// 6pt apart overlap while two small ones do not. At this instant the
    /// tightest pair clears by ~7pt; at zero it is 0.6pt, i.e. touching.
    ///
    /// Re-searched whenever `count` or the orbit parameters change: the field is
    /// entirely different at a different population, and a stale value here
    /// silently gives reduce-motion users a bunched-up frame. A first guess of
    /// 6.2 put two sparks 1.4pt apart — visually one dot; the test below caught it.
    static let stillInstant: TimeInterval = 286.65

    /// The field, generated once from a fixed seed.
    static let sparks: [Spark] = {
        var random = SeededGenerator(seed: 0x51F0_A2C7)
        return (0..<count).map { _ in
            Spark(
                radius: 0.19 + random.next() * 0.29,  // design-lint: allow radius-literal brand geometry, orbit radius as a share of width
                tilt: random.next() * .pi,
                squash: 0.18 + random.next() * 0.46,
                // Slow. These drift; they do not orbit at speed.
                speed: (0.10 + random.next() * 0.20) * (random.next() > 0.35 ? 1 : -1),
                phase: random.next() * 2 * .pi,
                size: 0.9 + random.next() * 1.9)
        }
    }()

    /// Where a spark is, and how near the viewer, at `now`.
    ///
    /// `depth` runs 0 (far side of its orbit) to 1 (near side) and drives three
    /// things at once — size, brightness, and whether the spark is drawn in front
    /// of the mark or behind it. One value for all three is what keeps them
    /// agreeing.
    static func position(
        _ spark: Spark,
        at now: TimeInterval,
        in width: CGFloat
    ) -> (point: CGPoint, depth: Double) {
        let angle = spark.phase + now * spark.speed
        let ex = cos(angle) * spark.radius * width
        let ey = sin(angle) * spark.radius * width * spark.squash
        let centre = width / 2
        let point = CGPoint(
            x: centre + ex * CGFloat(cos(spark.tilt)) - ey * CGFloat(sin(spark.tilt)),
            y: centre + ex * CGFloat(sin(spark.tilt)) + ey * CGFloat(cos(spark.tilt))
        )
        return (point, (sin(angle) + 1) / 2)
    }

    /// How strongly two sparks that far apart are linked. Zero at and beyond the
    /// threshold, so links fade in and out as orbits carry sparks together
    /// rather than switching on.
    static func linkStrength(distance: CGFloat, width: CGFloat) -> Double {
        let limit = linkDistance * width
        guard distance < limit, limit > 0 else { return 0 }
        return Double(1 - distance / limit)
    }
}

/// A tiny deterministic generator, so the field is identical on every launch.
///
/// Not `SystemRandomNumberGenerator`: this composition is art-directed, and a
/// layout that differs run to run cannot be. Not `Math.random`-equivalent
/// either — the values must be reproducible in tests.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value in 0..<1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
