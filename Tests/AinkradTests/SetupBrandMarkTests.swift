import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// The mark's silhouette, pinned against the measurements taken from the source
/// artwork.
///
/// These exist because the first version of this shape was drawn by eye and was
/// visibly not the logo — swept outer edges instead of straight ones, and a
/// crystal tapering the wrong way. A shape is the one kind of view whose
/// correctness IS a set of numbers, so it can be tested rather than only looked
/// at, and every probe below is a proportion measured off the PNG.
@Suite("Setup brand mark")
struct SetupBrandMarkTests {
    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func chevron() -> Path { AinkradChevronMark().path(in: box) }
    private func crystal() -> Path { AinkradCrystalMark().path(in: box) }

    // MARK: Chevron

    // The V cut into the underside is what makes this the Ainkrad mark rather
    // than a solid triangle — and it is where the crystal sits.
    @Test func theUndersideIsNotched() {
        // Above the notch apex (0.572 down) the mark is solid…
        #expect(chevron().contains(CGPoint(x: 50, y: 30)))
        // …and below it, the centre line is empty.
        #expect(!chevron().contains(CGPoint(x: 50, y: 75)))
        #expect(!chevron().contains(CGPoint(x: 50, y: 95)))
    }

    // Straight, not swept. A curved edge bows INSIDE the apex-to-corner line, so
    // probing just inside that line catches the earlier hand-drawn version.
    @Test func theOuterEdgesRunStraightFromApexToCorner() {
        for v in stride(from: 0.2, through: 0.9, by: 0.1) {
            // The straight edge is at u = 0.5 - 0.5v on the left.
            let edge = (0.5 - 0.5 * v) * 100
            #expect(
                chevron().contains(CGPoint(x: edge + 2.5, y: v * 100)),
                "the left edge should be solid just inside u=\(edge) at v=\(v)")
            #expect(
                !chevron().contains(CGPoint(x: edge - 2.5, y: v * 100)),
                "…and empty just outside it")
        }
    }

    // The inner edges are steeper than the outer ones, which is what tapers each
    // wing toward its tip. Equal slopes would give parallel-sided wings.
    @Test func theWingsTaperTowardTheirTips() {
        func wingWidth(atV v: Double) -> Double {
            let ys = v * 100
            let solid = stride(from: 0.0, through: 50.0, by: 0.25)
                .filter { chevron().contains(CGPoint(x: $0, y: ys)) }
            return (solid.max() ?? 0) - (solid.min() ?? 0)
        }
        // Measured just below the notch apex, and again near the baseline.
        #expect(wingWidth(atV: 0.70) > wingWidth(atV: 0.95))
    }

    @Test func theApexIsCentredAtTheTop() {
        #expect(chevron().contains(CGPoint(x: 50, y: 4)))
        #expect(!chevron().contains(CGPoint(x: 20, y: 4)))
        #expect(!chevron().contains(CGPoint(x: 80, y: 4)))
    }

    // MARK: Crystal

    // Widest BELOW its middle: it tapers long toward the top and short toward
    // the bottom. Getting this backwards was the second silhouette error, and it
    // is invisible unless something measures it.
    @Test func theCrystalIsWidestBelowItsMiddle() {
        func width(atY y: Double) -> Double {
            let solid = stride(from: 0.0, through: 100.0, by: 0.25)
                .filter { crystal().contains(CGPoint(x: $0, y: y)) }
            return (solid.max() ?? 0) - (solid.min() ?? 0)
        }
        let shoulder = Double(AinkradCrystalMark.shoulder) * 100
        #expect(shoulder > 50, "the widest point must sit below the vertical middle")
        #expect(width(atY: shoulder) > width(atY: 50))
        #expect(width(atY: shoulder) > width(atY: 85))
        // The taper toward the top runs over a longer distance, so its sides are
        // SHALLOWER — at equal distances from the shoulder the upper half is
        // therefore wider. Confirmed against the traced rows of the source art:
        // 0.168 of the mark's width above the shoulder against 0.127 below it.
        #expect(width(atY: shoulder - 20) > width(atY: shoulder + 20))
    }

    // MARK: Orbit field

    // Sparks travel elliptical orbits and link up when they drift near each
    // other. All of it is pure arithmetic precisely so it can be asserted at
    // times nobody would sit and watch.

    // A first-run screen that composes differently on every launch cannot be
    // art-directed. The seed is what makes it the same picture every time.
    @Test func theFieldIsIdenticalOnEveryLaunch() {
        #expect(SetupOrbitField.sparks.count == SetupOrbitField.count)
        // Reading it twice must give the same field — a lazily-initialised
        // static seeded from a system generator would not.
        #expect(SetupOrbitField.sparks == SetupOrbitField.sparks)
        // And the sparks must genuinely differ from each other, rather than the
        // generator returning one value repeatedly.
        #expect(Set(SetupOrbitField.sparks.map(\.phase)).count == SetupOrbitField.count)
        #expect(Set(SetupOrbitField.sparks.map(\.radius)).count == SetupOrbitField.count)
    }

    // Orbits must differ in TILT, or twenty sparks read as one flat ring — which
    // is the shape this effect exists to get away from.
    @Test func orbitsAreTiltedIndependently() {
        #expect(Set(SetupOrbitField.sparks.map(\.tilt)).count == SetupOrbitField.count)
        // Some run backwards, so the field never reads as one rotating object.
        let reversed = SetupOrbitField.sparks.filter { $0.speed < 0 }
        #expect(!reversed.isEmpty && reversed.count < SetupOrbitField.count)
    }

    // Sparks must stay inside the composition at every point of every orbit,
    // or they clip at the edge of the frame.
    @Test func everySparkStaysWithinTheComposition() {
        let width: CGFloat = 236
        for spark in SetupOrbitField.sparks {
            for step in 0..<80 {
                let now = Double(step) * 0.9
                let (point, _) = SetupOrbitField.position(spark, at: now, in: width)
                #expect(point.x >= 0 && point.x <= width)
                #expect(point.y >= 0 && point.y <= width)
            }
        }
    }

    // Depth drives size, brightness AND which side of the mark a spark is drawn
    // on, so it has to stay a clean 0...1 forever.
    @Test func depthStaysNormalisedAtAnyTime() {
        for now in [0.0, 7.5, 3_600.0, 604_800.0] {
            for spark in SetupOrbitField.sparks {
                let (_, depth) = SetupOrbitField.position(spark, at: now, in: 236)
                #expect(depth >= 0 && depth <= 1)
            }
        }
    }

    // The mark sits on top of the ENTIRE field — see `SetupBrandMark.composition`.
    // Depth therefore no longer decides what is drawn in front; it varies each
    // spark's size and brightness so the field still reads as having near and
    // far, without anything ever crossing the logo.
    @Test func depthVariesAcrossEachSparksOwnOrbit() {
        for (index, spark) in SetupOrbitField.sparks.enumerated() {
            var lowest = 1.0
            var highest = 0.0
            for step in 0..<400 {
                let (_, depth) = SetupOrbitField.position(spark, at: Double(step) * 0.4, in: 236)
                lowest = min(lowest, depth)
                highest = max(highest, depth)
            }
            // Close to the full 0...1 sweep: a spark whose depth barely moved
            // would be a dot of fixed size and brightness, which is the flat
            // look this field exists to avoid.
            #expect(highest - lowest > 0.9, "spark \(index) barely changes depth")
        }
    }

    // Links fade in and out with distance rather than switching on, which is
    // what stops them flickering as sparks drift across the threshold.
    @Test func linksFadeInWithProximity() {
        let width: CGFloat = 236
        let limit = SetupOrbitField.linkDistance * width
        #expect(SetupOrbitField.linkStrength(distance: limit, width: width) == 0)
        #expect(SetupOrbitField.linkStrength(distance: limit * 2, width: width) == 0)
        #expect(SetupOrbitField.linkStrength(distance: 0, width: width) == 1)
        // Monotonic between those two, so there is no distance at which moving
        // closer makes a link fainter.
        var previous = 1.0
        for step in 1...40 {
            let strength = SetupOrbitField.linkStrength(
                distance: limit * CGFloat(step) / 40,
                width: width)
            #expect(strength <= previous)
            previous = strength
        }
    }

    // A zero-width composition must not divide by zero into a NaN opacity, which
    // renders as an invisible or fully-opaque line rather than crashing.
    @Test func linksSurviveADegenerateWidth() {
        let strength = SetupOrbitField.linkStrength(distance: 0, width: 0)
        #expect(strength == 0)
        #expect(!strength.isNaN)
    }

    // Reduce-motion freezes the field at a chosen instant. That instant has to
    // be one where the orbits have SPREAD — at zero several sparks bunch at
    // their phase origins and the still frame looks unresolved.
    @Test func theStillInstantIsAComposedOne() {
        // The gap between the closest pair's DRAWN EDGES, not their centres:
        // two large sparks 6pt apart overlap while two small ones do not, so a
        // centre-distance threshold would pass a frame that visibly blobs.
        func tightestGap(at now: TimeInterval) -> CGFloat {
            let width: CGFloat = 236
            let scale = width / SetupOrbitField.referenceWidth
            let placed = SetupOrbitField.sparks.map { spark -> (CGPoint, CGFloat) in
                let (point, depth) = SetupOrbitField.position(spark, at: now, in: width)
                return (point, spark.size * (0.6 + CGFloat(depth) * 0.7) * scale)
            }
            var gap = CGFloat.greatestFiniteMagnitude
            for i in placed.indices {
                for j in (i + 1)..<placed.count {
                    let distance = hypot(
                        placed[i].0.x - placed[j].0.x,
                        placed[i].0.y - placed[j].0.y)
                    gap = min(gap, distance - (placed[i].1 + placed[j].1))
                }
            }
            return gap
        }

        // No two sparks may overlap at all in the frozen frame…
        #expect(tightestGap(at: SetupOrbitField.stillInstant) > 3)
        // …and it must be a real improvement on the phase origin, where they
        // bunch.
        #expect(tightestGap(at: SetupOrbitField.stillInstant) > tightestGap(at: 0))

        // A plateau, not a spike: nudging the instant either way must not
        // collapse the composition, or the value is fragile against any later
        // tuning of the orbits.
        for offset in [-0.6, -0.3, 0.3, 0.6] {
            #expect(
                tightestGap(at: SetupOrbitField.stillInstant + offset) > 0,
                "sparks overlap \(offset)s from the chosen instant")
        }
    }

    @Test func theCrystalIsAClosedKiteOnTheCentreLine() {
        #expect(crystal().contains(CGPoint(x: 50, y: 50)))
        #expect(crystal().contains(CGPoint(x: 50, y: 90)))
        // Corners are outside a kite, which a rectangle or an ellipse would not
        // agree with.
        #expect(!crystal().contains(CGPoint(x: 5, y: 5)))
        #expect(!crystal().contains(CGPoint(x: 95, y: 95)))
    }
}
