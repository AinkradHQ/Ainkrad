import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

// MARK: - Shapes
//
// Both paths are TRACED from the source artwork
// (`island-layers-ai/chevron.png`), not drawn by eye. Every constant below is a
// measured proportion of the mark's own bounding box, taken by sampling the
// PNG's alpha and splitting body pixels from crystal pixels by hue. An earlier
// hand-drawn version got the silhouette visibly wrong — the outer edges are
// straight, not swept, and the crystal is widest BELOW its middle.
//
// Drawn as paths rather than shipped as the PNG because the artwork bakes in a
// white body and a cyan core, which cannot be retinted per theme, and because a
// path stays crisp at the 200pt-plus this screen shows it at.

/// The arrowhead: an apex at top centre, two straight-edged wings falling to the
/// baseline, and a V cut up into the underside.
///
/// Measured proportions, in the shape's own box:
/// - the outer edges run straight from the apex to the bottom corners
/// - each wing's bottom edge is short — it reaches `0.13` in from the corner
/// - the notch apex sits at `0.572` down, and the inner edges are markedly
///   steeper than the outer ones, which is what tapers the wings
struct AinkradChevronMark: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.5, 0))          // apex
        path.addLine(to: p(1.0, 1.0))     // outer right, straight
        path.addLine(to: p(0.87, 1.0))    // right wing's bottom edge
        path.addLine(to: p(0.5, 0.572))   // up the inner right edge to the notch
        path.addLine(to: p(0.13, 1.0))    // down the inner left edge
        path.addLine(to: p(0.0, 1.0))     // left wing's bottom edge
        path.closeSubpath()               // outer left, straight, back to the apex
        return path
    }
}

/// The crystal core that sits in the chevron's notch.
///
/// A kite whose widest point is at `0.626` down — below centre, so it tapers
/// long toward the top and short toward the bottom. Getting this backwards
/// makes it read as a gemstone icon rather than this mark's core.
struct AinkradCrystalMark: Shape {
    /// Where the kite reaches full width, as a fraction of its height. Shared
    /// with the facet below so the two cannot disagree.
    static let shoulder: CGFloat = 0.626

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.5, 0))
        path.addLine(to: p(1.0, Self.shoulder))
        path.addLine(to: p(0.5, 1.0))
        path.addLine(to: p(0.0, Self.shoulder))
        path.closeSubpath()
        return path
    }
}

/// The crystal's left facet, overlaid to catch the light on one side only. A
/// flat-filled kite reads as a sticker; one lit face gives it volume.
private struct AinkradCrystalFacet: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.5, 0))
        path.addLine(to: p(0.5, 1.0))
        path.addLine(to: p(0.0, AinkradCrystalMark.shoulder))
        path.closeSubpath()
        return path
    }
}

// MARK: - Proportions

/// The measured relationships between the mark's parts, so the pair stays
/// correct at any size and no call site re-derives them.
private enum MarkProportions {
    /// Crystal width, as a fraction of the chevron's width.
    static let crystalWidth: CGFloat = 0.220
    /// Crystal height, as a fraction of the chevron's HEIGHT.
    static let crystalHeight: CGFloat = 0.427
    /// How far down the chevron the crystal's top point sits.
    static let crystalTop: CGFloat = 0.741
    /// The chevron's own aspect: height as a fraction of width.
    static let chevronAspect: CGFloat = 131.0 / 173.0
}

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
            Spark(radius: 0.19 + random.next() * 0.29,
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
    static func position(_ spark: Spark,
                         at now: TimeInterval,
                         in width: CGFloat) -> (point: CGPoint, depth: Double) {
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

// MARK: - The mark

/// The wizard's brand hero: the mark centred inside its halo rings.
///
/// Deliberately NOT shared with `EmblemView`, which still draws the older "A"
/// mark on an empty workspace. Two marks in one product is a real inconsistency
/// and it is recorded rather than hidden — unifying them changes a screen
/// outside this branch's scope, so it is a follow-up, not a side effect.
///
/// **Motion is driven by `TimelineView`, not by animating state.** The first
/// version flipped an `@State` flag in `onAppear` and hung `repeatForever`
/// animations off it; nothing moved. A continuously-running ambient composition
/// is not a state transition, and expressing it as one puts it at the mercy of
/// every ancestor that owns an `.animation` — and this view has two (the step's
/// entry stagger and the stage's transition). Reading the clock instead cannot
/// be cancelled from above and needs no driver state at all.
///
/// The layers follow the design language's "separated live layers, not one whole
/// image moving". ALL of the motion belongs to the sparks: four dashed rings
/// expanding outward from behind the mark, each drifting round at its own rate
/// and direction. The mark and its halo are STILL — they only glow. An earlier
/// version had the mark breathing too, which put two competing rhythms on one
/// small composition and made the logo look loose rather than lit.
struct SetupBrandMark: View {
    /// How the mark is being used, which decides what is drawn around it.
    ///
    /// The two are the same glyph at different jobs, not two different marks:
    /// `hero` is the Welcome screen's subject and earns the whole spark field;
    /// `inline` is an identifying mark beside a heading, where a field of
    /// drifting sparks the size of a word would be noise.
    enum Style: Equatable {
        /// The full composition — sparks, halo, glow — at `diameter` across.
        case hero(diameter: CGFloat)
        /// Glyph and glow only, with the CHEVRON sized to `height` so the mark
        /// optically matches the text it sits beside.
        case inline(height: CGFloat)
    }

    let tokens: DesignTokens
    let reduceMotion: Bool
    var style: Style = .hero(diameter: 236)

    /// The box the composition is laid out in.
    private var diameter: CGFloat {
        switch style {
        case .hero(let diameter): return diameter
        // Sized from the chevron rather than the other way round: what has to
        // match the heading is the GLYPH, and the box is whatever contains it.
        case .inline(let height): return height / MarkProportions.chevronAspect / 0.9
        }
    }

    /// The chevron's width. In `hero` the pulse rings are born smaller than this
    /// and grow out past the composition's edge, so the mark is what they
    /// emanate from; in `inline` the glyph nearly fills its box.
    private var chevronWidth: CGFloat {
        switch style {
        case .hero: return diameter * 0.44
        case .inline: return diameter * 0.9
        }
    }

    private var showsField: Bool {
        if case .hero = style { return true }
        return false
    }

    var body: some View {
        Group {
            if reduceMotion || !showsField {
                composition(isStatic: true)
            } else {
                BudgetedTimelineView { date in
                    composition(isStatic: false,
                                now: date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        // One element, described. Six pulse rings and a glow are decoration,
        // and announcing each would be noise.
        .accessibilityElement()
        .accessibilityLabel("The Ainkrad mark")
    }

    // MARK: Composition

    /// `isStatic` freezes the field for reduce-motion.
    private func composition(isStatic: Bool, now: TimeInterval = 0) -> some View {
        // Explicit `zIndex` rather than relying on declaration order alone.
        // Declaration order already gives the right result, but the requirement
        // is load-bearing enough to say twice — reordering these lines in some
        // later edit would silently break it.
        ZStack {
            if showsField {
                field(isStatic: isStatic, now: now).zIndex(0)
                halo.zIndex(1)
            }
            // THE MARK IS ON TOP OF EVERYTHING. Nothing in this composition may
            // be layered above it — no spark, no link, no glow. An earlier
            // version drew the near half of the field in front, which gave more
            // depth but let dots cross the logo; the logo wins.
            mark.zIndex(2)
        }
    }

    // MARK: Orbit field

    /// The whole field, in one layer BEHIND the mark.
    ///
    /// `Scry` rather than a stack of `Circle` views: the links are recomputed
    /// every frame from every pair of sparks, which is drawing rather than view
    /// structure — and twenty views each carrying their own shadow would cost far
    /// more than one immediate-mode pass.
    ///
    /// Depth still varies each spark's size and brightness, so the field keeps
    /// its sense of near and far; what it no longer does is put anything in
    /// front of the logo.
    private func field(isStatic: Bool, now: TimeInterval) -> some View {
        // Reduce-motion freezes the clock at an instant chosen to look composed,
        // rather than at zero where several sparks sit bunched at their phase
        // origins.
        let t = isStatic ? SetupOrbitField.stillInstant : now

        return Canvas { context, size in
            let width = size.width
            let placed = SetupOrbitField.sparks.map {
                SetupOrbitField.position($0, at: t, in: width)
            }
            let scale = width / SetupOrbitField.referenceWidth

            drawLinks(in: context, placed: placed, width: width, scale: scale)

            for (index, spark) in SetupOrbitField.sparks.enumerated() {
                let (point, depth) = placed[index]
                // Depth drives size and brightness together, so a spark on the
                // far side of its orbit is small AND dim rather than one or the
                // other.
                let radius = spark.size * (0.6 + CGFloat(depth) * 0.7) * scale
                let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                  width: radius * 2, height: radius * 2)

                // The bloom is a second, blurred, oversized dot rather than a
                // shadow: `Scry` has no per-shape shadow, and this is what
                // makes a spark read as a light rather than a dot.
                var bloom = context
                bloom.addFilter(.blur(radius: radius * 1.5))
                bloom.opacity = 0.5 * (0.3 + depth * 0.7)
                bloom.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)),
                           with: .color(tokens.accentSecondary))

                var dot = context
                dot.opacity = 0.30 + depth * 0.65
                dot.fill(Path(ellipseIn: rect), with: .color(tokens.accentSecondary))
            }
        }
        .allowsHitTesting(false)
    }

    /// Links between sparks that have drifted near each other.
    ///
    /// Every pair is tested — 190 distance checks for twenty sparks, which is
    /// nothing — so a link appears wherever two sparks actually pass, rather
    /// than only along pairings fixed in advance.
    private func drawLinks(in context: GraphicsContext,
                           placed: [(point: CGPoint, depth: Double)],
                           width: CGFloat,
                           scale: CGFloat) {
        for i in placed.indices {
            for j in (i + 1)..<placed.count {
                let a = placed[i], b = placed[j]
                let distance = hypot(a.point.x - b.point.x, a.point.y - b.point.y)
                let strength = SetupOrbitField.linkStrength(distance: distance, width: width)
                guard strength > 0 else { continue }

                var line = Path()
                line.move(to: a.point)
                line.addLine(to: b.point)

                // Faint, and further dimmed by how far back the pair is: a link
                // between two distant sparks should not be as present as one
                // between two near ones.
                var stroked = context
                stroked.opacity = strength * 0.4 * (0.35 + (a.depth + b.depth) / 2 * 0.65)
                stroked.stroke(line,
                               with: .color(tokens.accentPrimary),
                               lineWidth: 0.9 * scale)
            }
        }
    }

    /// Steady, not breathing. With the mark itself now still, a pulsing halo
    /// would be the only thing swelling and would read as the mark breathing
    /// anyway — the motion in this composition belongs entirely to the sparks.
    private var halo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tokens.accentPrimary.opacity(0.42),
                             tokens.accentPrimary.opacity(0.10),
                             .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: diameter * 0.52
                )
            )
    }

    // MARK: The mark

    /// Chevron and crystal, sized and placed from the measured proportions.
    ///
    /// Completely still, and lit hard. The glow is layered — a tight bright
    /// bloom over a wide soft one — because a single large shadow just greys the
    /// area around the shape, while two at different radii read as a light
    /// source with falloff.
    private var mark: some View {
        let chevronHeight = chevronWidth * MarkProportions.chevronAspect
        let crystalW = chevronWidth * MarkProportions.crystalWidth
        let crystalH = chevronHeight * MarkProportions.crystalHeight
        // The crystal hangs below the chevron's baseline, so the pair is taller
        // than the chevron alone — centre the PAIR, not the chevron.
        let pairHeight = chevronHeight * MarkProportions.crystalTop + crystalH

        return ZStack(alignment: .top) {
            AinkradChevronMark()
                .fill(
                    LinearGradient(
                        colors: [tokens.foreground, tokens.foreground.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: chevronWidth, height: chevronHeight)
                .shadow(color: tokens.accentSecondary.opacity(0.55), radius: 8)
                .shadow(color: tokens.accentPrimary.opacity(0.75), radius: 26)

            crystal(width: crystalW, height: crystalH)
                .offset(y: chevronHeight * MarkProportions.crystalTop)
        }
        .frame(width: chevronWidth, height: pairHeight, alignment: .top)
    }

    /// The crystal is the brightest thing in the composition — it is the core.
    /// Three stacked shadows, tight to wide, so it genuinely reads as emitting
    /// rather than as a cyan shape with a blur behind it.
    private func crystal(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            AinkradCrystalMark()
                .fill(
                    LinearGradient(
                        colors: [tokens.accentSecondary, tokens.accentPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            AinkradCrystalFacet()
                .fill(tokens.foreground.opacity(0.28))
        }
        .frame(width: width, height: height)
        .shadow(color: tokens.accentSecondary.opacity(0.95), radius: 6)
        .shadow(color: tokens.accentSecondary.opacity(0.7), radius: 16)
        .shadow(color: tokens.accentSecondary.opacity(0.4), radius: 34)
    }
}
