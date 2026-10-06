import CoreGraphics
import Testing

@testable import Ainkrad

@Suite("SkyMath stars")
struct SkyMathStarTests {

    @Test("the field is deterministic and well-formed")
    func fieldWellFormed() {
        for index in 0..<SkyMath.starCount {
            let star = SkyMath.star(index: index)
            #expect(star == SkyMath.star(index: index))
            #expect((0.0...1.0).contains(star.x))
            #expect((0.0...1.0).contains(star.y))
            #expect(star.radius > 0.3 && star.radius < 2.5)
            #expect(star.baseOpacity > 0.05 && star.baseOpacity < 0.6)
            #expect((0...2).contains(star.depth))
        }
    }

    @Test("every depth band exists and far stars outnumber near ones")
    func depthDistribution() {
        let stars = (0..<SkyMath.starCount).map { SkyMath.star(index: $0) }
        let far = stars.filter { $0.depth == 0 }.count
        let mid = stars.filter { $0.depth == 1 }.count
        let near = stars.filter { $0.depth == 2 }.count
        #expect(far > 0 && mid > 0 && near > 0)
        #expect(far > near)
    }
}

@Suite("SkyMath drift")
struct SkyMathDriftTests {

    @Test("every star is in motion — no zero velocities")
    func everyStarMoves() {
        for index in 0..<SkyMath.starCount {
            let star = SkyMath.star(index: index)
            let speed = (star.vx * star.vx + star.vy * star.vy).squareRoot()
            #expect(speed > 0.0005, "star \(index) is effectively stationary")
        }
    }

    @Test("drift directions scatter randomly — all four axis signs are common")
    func directionsScatter() {
        let stars = (0..<SkyMath.starCount).map { SkyMath.star(index: $0) }
        let minimum = SkyMath.starCount / 10
        #expect(stars.filter { $0.vx > 0 }.count >= minimum)
        #expect(stars.filter { $0.vx < 0 }.count >= minimum)
        #expect(stars.filter { $0.vy > 0 }.count >= minimum)
        #expect(stars.filter { $0.vy < 0 }.count >= minimum)
    }

    @Test("positions drift measurably, deterministically, and wrap into 0…1 forever")
    func positionsDriftAndWrap() {
        for index in stride(from: 0, to: SkyMath.starCount, by: 7) {
            let origin = SkyMath.position(index: index, time: 0)
            var moved = false
            // Include a far-future instant: the motion never settles or ends.
            for time in [3.0, 9.0, 31.0, 100_000.0] {
                let point = SkyMath.position(index: index, time: time)
                #expect(point == SkyMath.position(index: index, time: time))
                #expect((0.0...1.0).contains(point.x))
                #expect((0.0...1.0).contains(point.y))
                if hypot(point.x - origin.x, point.y - origin.y) > 0.004 { moved = true }
            }
            #expect(moved, "star \(index) never left its origin")
        }
    }

    @Test("twinkle stays within its brightness band and actually varies")
    func twinkleBounds() {
        var spread = 0.0
        for index in [0, 7, 42, 99] {
            var low = 2.0
            var high = -1.0
            for step in 0..<600 {
                let value = SkyMath.twinkle(index: index, time: Double(step) * 0.1)
                #expect(value >= 0.3 && value <= 1.0)
                low = min(low, value)
                high = max(high, value)
            }
            spread = max(spread, high - low)
        }
        #expect(spread > 0.2)
    }

    @Test("glints are bounded, sparse, and deterministic")
    func glintSparse() {
        var active = 0
        var samples = 0
        for index in [0, 5, 23, 77, 131] {
            for step in 0..<4000 {
                let time = Double(step) * 0.25  // 1000 s sweep
                let value = SkyMath.glint(index: index, time: time)
                #expect(value >= 0 && value <= 1)
                #expect(value == SkyMath.glint(index: index, time: time))
                if value > 0 { active += 1 }
                samples += 1
            }
        }
        #expect(Double(active) / Double(samples) < 0.2)
        #expect(active > 0)  // they do happen
    }
}

@Suite("SkyMath aurora")
struct SkyMathAuroraTests {

    @Test("segments are deterministic, bounded to the upper sky, and gentle")
    func segmentsWellFormed() {
        for ribbon in 0..<SkyMath.auroraRibbons {
            for segment in 0..<SkyMath.auroraSegments {
                for step in 0..<240 {
                    let time = Double(step) * 0.5  // 2-minute sweep
                    let blob = SkyMath.auroraSegment(ribbon: ribbon, segment: segment, time: time)
                    #expect(blob == SkyMath.auroraSegment(ribbon: ribbon, segment: segment, time: time))
                    #expect((0.0...1.0).contains(blob.x))
                    #expect((0.0...0.5).contains(blob.y))  // upper sky only
                    #expect(blob.radiusX > 0.03 && blob.radiusX < 0.25)
                    #expect(blob.radiusY > 0.005 && blob.radiusY < 0.12)
                    #expect(blob.opacity >= 0 && blob.opacity <= 0.14)  // always subtle
                }
            }
        }
    }

    @Test("ribbons sway and shimmer — never a frozen band")
    func ribbonsMove() {
        var positionSpread = 0.0
        var opacitySpread = 0.0
        for ribbon in 0..<SkyMath.auroraRibbons {
            let segment = SkyMath.auroraSegments / 2
            var minX = 2.0
            var maxX = -1.0
            var minOpacity = 2.0
            var maxOpacity = -1.0
            for step in 0..<600 {
                let blob = SkyMath.auroraSegment(ribbon: ribbon, segment: segment, time: Double(step) * 0.4)
                minX = min(minX, blob.x)
                maxX = max(maxX, blob.x)
                minOpacity = min(minOpacity, blob.opacity)
                maxOpacity = max(maxOpacity, blob.opacity)
            }
            positionSpread = max(positionSpread, maxX - minX)
            opacitySpread = max(opacitySpread, maxOpacity - minOpacity)
        }
        #expect(positionSpread > 0.005)
        #expect(opacitySpread > 0.015)
    }

    @Test("the aurora is always faintly present — it shimmers, it never dies")
    func neverDies() {
        for step in 0..<200 {
            let time = Double(step) * 3.7
            var total = 0.0
            for ribbon in 0..<SkyMath.auroraRibbons {
                for segment in 0..<SkyMath.auroraSegments {
                    total += SkyMath.auroraSegment(ribbon: ribbon, segment: segment, time: time).opacity
                }
            }
            #expect(total > 0.1)
        }
    }
}

@Suite("SkyMath atmosphere")
struct SkyMathAtmosphereTests {

    @Test("breath cycles slowly within 0…1 and never stalls")
    func breathCycles() {
        var low = 2.0
        var high = -1.0
        for step in 0..<3000 {
            let value = SkyMath.breath(time: Double(step) * 0.1)  // 5-minute sweep
            #expect(value >= 0 && value <= 1)
            #expect(value == SkyMath.breath(time: Double(step) * 0.1))
            low = min(low, value)
            high = max(high, value)
        }
        #expect(high - low > 0.4)
    }

    @Test("mist bands hug the horizon, stay faint, and keep sliding forever")
    func mistBands() {
        for index in 0..<SkyMath.mistBands {
            var minX = 2.0
            var maxX = -1.0
            for step in 0..<1200 {
                let time = Double(step) * 0.5
                let band = SkyMath.mistBand(index: index, time: time)
                #expect(band == SkyMath.mistBand(index: index, time: time))
                #expect((0.0...1.0).contains(band.x))
                #expect((0.7...1.0).contains(band.y))  // horizon region only
                #expect(band.radiusX > 0.1 && band.radiusX < 0.6)
                #expect(band.radiusY > 0.01 && band.radiusY < 0.15)
                #expect(band.opacity > 0 && band.opacity <= 0.07)  // always faint
                minX = min(minX, band.x)
                maxX = max(maxX, band.x)
            }
            #expect(maxX - minX > 0.3)  // slides across, wrapping
        }
    }

    @Test("light rays fan out from the horizon sun, sway slowly, and stay subtle")
    func lightRays() {
        var swayed = false
        for index in 0..<SkyMath.lightRayCount {
            let first = SkyMath.lightRay(index: index, time: 0)
            for step in 0..<600 {
                let time = Double(step) * 0.5
                let ray = SkyMath.lightRay(index: index, time: time)
                #expect(ray == SkyMath.lightRay(index: index, time: time))
                #expect(abs(ray.angle) < 0.8)  // never horizontal
                #expect(ray.width > 0.02 && ray.width < 0.15)
                #expect(ray.opacity > 0 && ray.opacity <= 0.08)  // always subtle
                if abs(ray.angle - first.angle) > 0.01 { swayed = true }
            }
        }
        #expect(swayed)
    }
}

@Suite("SkyMath fireflies and bokeh")
struct SkyMathForegroundTests {

    @Test("fireflies stay in the island's region, pulse, and keep rising")
    func fireflies() {
        #expect(SkyMath.fireflyCount >= 20)  // a lively swarm, per review
        for index in 0..<SkyMath.fireflyCount {
            var minOpacity = 2.0
            var maxOpacity = -1.0
            var positions = Set<Int>()
            for step in 0..<800 {
                let time = Double(step) * 0.25
                let fly = SkyMath.firefly(index: index, time: time)
                #expect(fly == SkyMath.firefly(index: index, time: time))
                #expect((0.25...0.75).contains(fly.x))  // island zone
                #expect((0.18...0.82).contains(fly.y))
                #expect(fly.radius > 0.5 && fly.radius < 3.0)
                #expect(fly.opacity >= 0 && fly.opacity <= 0.7)
                minOpacity = min(minOpacity, fly.opacity)
                maxOpacity = max(maxOpacity, fly.opacity)
                positions.insert(Int(fly.y * 1000))
            }
            #expect(maxOpacity - minOpacity > 0.1)  // visibly pulses
            #expect(positions.count > 50)  // travels its column
        }
    }

    @Test("bokeh orbs are large, ultra-faint, and drift very slowly")
    func bokeh() {
        for index in 0..<SkyMath.bokehCount {
            let origin = SkyMath.bokehOrb(index: index, time: 0)
            var moved = false
            for step in 0..<400 {
                let time = Double(step) * 1.0
                let orb = SkyMath.bokehOrb(index: index, time: time)
                #expect(orb == SkyMath.bokehOrb(index: index, time: time))
                #expect((0.0...1.0).contains(orb.x))
                #expect((0.0...1.0).contains(orb.y))
                #expect(orb.radius > 0.02 && orb.radius < 0.10)
                #expect(orb.opacity > 0 && orb.opacity <= 0.06)  // ultra faint
                if hypot(orb.x - origin.x, orb.y - origin.y) > 0.003 { moved = true }
            }
            #expect(moved)
        }
    }
}
