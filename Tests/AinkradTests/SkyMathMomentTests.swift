import CoreGraphics
import Testing

@testable import Ainkrad

@Suite("SkyMath embers")
struct SkyMathEmberTests {

    @Test("embers are bounded, deterministic, and all rising in normalized space")
    func embersWellFormed() {
        for index in 0..<SkyMath.emberCount {
            var ys = Set<Int>()
            for step in 0..<400 {
                let time = Double(step) * 0.5
                let ember = SkyMath.ember(index: index, time: time)
                #expect(ember == SkyMath.ember(index: index, time: time))
                #expect((0.0...1.0).contains(ember.x))
                #expect((0.0...1.0).contains(ember.y))
                #expect(ember.radius > 0.4 && ember.radius < 2.2)
                #expect(ember.opacity >= 0 && ember.opacity <= 0.55)
                ys.insert(Int(ember.y * 1000))
            }
            #expect(ys.count > 40)  // travels its column, wrapping forever
        }
    }

    @Test("embers rise — y decreases between nearby instants unless wrapping")
    func embersRise() {
        for index in stride(from: 0, to: SkyMath.emberCount, by: 9) {
            let before = SkyMath.ember(index: index, time: 10)
            let after = SkyMath.ember(index: index, time: 11)
            let wrapped = after.y > before.y + 0.5
            #expect(after.y < before.y || wrapped)
        }
    }
}

@Suite("SkyMath sky moments")
struct SkyMathMomentTests {

    @Test("meteor showers are rare bursts of 3–5 valid streaks")
    func meteorShowers() {
        var activeSamples = 0
        var appearances = 0
        var wasActive = false
        for step in 0..<4800 {
            let time = Double(step) * 0.5  // 40-minute sweep
            let streaks = SkyMath.meteorShower(time: time)
            #expect(streaks == SkyMath.meteorShower(time: time))
            if streaks.isEmpty {
                wasActive = false
            } else {
                activeSamples += 1
                if !wasActive { appearances += 1 }
                wasActive = true
                #expect(streaks.count <= 5)
                for streak in streaks {
                    #expect((0.0...1.0).contains(streak.progress))
                    #expect((0.0...1.0).contains(streak.startX))
                    #expect((0.0...0.5).contains(streak.startY))
                }
            }
        }
        #expect(Double(activeSamples) / 4800.0 < 0.05)  // rare
        #expect(appearances >= 1)
        #expect(appearances <= 8)
    }

    @Test("the comet is rarer still, slow, and always in the upper sky")
    func comet() {
        var activeSamples = 0
        var appearances = 0
        var wasActive = false
        for step in 0..<4800 {
            let time = Double(step) * 0.5  // 40-minute sweep
            let comet = SkyMath.comet(time: time)
            #expect(comet == SkyMath.comet(time: time))
            if let comet {
                activeSamples += 1
                if !wasActive { appearances += 1 }
                wasActive = true
                #expect((0.0...1.0).contains(comet.progress))
                #expect((0.0...1.0).contains(comet.startX))
                #expect((0.0...0.4).contains(comet.startY))
                #expect(comet.brightness >= 0 && comet.brightness <= 1)
            } else {
                wasActive = false
            }
        }
        #expect(Double(activeSamples) / 4800.0 < 0.05)
        #expect(appearances >= 1)
        #expect(appearances <= 6)
    }

    @Test("aurora surges are occasional, bounded blooms")
    func auroraSurge() {
        var activeSamples = 0
        var appearances = 0
        var wasActive = false
        for step in 0..<4800 {
            let time = Double(step) * 0.5  // 40-minute sweep
            let surge = SkyMath.auroraSurge(time: time)
            #expect(surge == SkyMath.auroraSurge(time: time))
            #expect(surge >= 0 && surge <= 1)
            if surge > 0 {
                activeSamples += 1
                if !wasActive { appearances += 1 }
                wasActive = true
            } else {
                wasActive = false
            }
        }
        #expect(Double(activeSamples) / 4800.0 < 0.1)
        #expect(appearances >= 2)
        #expect(appearances <= 16)
    }
}

@Suite("SkyMath weather")
struct SkyMathWeatherTests {

    @Test("the mood drifts slowly across its whole range and never jumps")
    func weatherDrifts() {
        var low = 2.0
        var high = -1.0
        var previous: Double?
        for step in 0..<3600 {
            let time = Double(step) * 0.5  // 30-minute sweep
            let value = SkyMath.weather(time: time)
            #expect(value >= 0 && value <= 1)
            #expect(value == SkyMath.weather(time: time))
            if let previous { #expect(abs(value - previous) < 0.02) }  // never jumps
            previous = value
            low = min(low, value)
            high = max(high, value)
        }
        #expect(high - low > 0.5)  // actually travels between moods
    }
}

@Suite("SkyMath sky traffic")
struct SkyMathVesselTests {

    @Test("vessels cross every few minutes, high in the sky, and always fade at the edges")
    func vesselsRareAndBounded() {
        var activeSamples = 0
        var appearances = 0
        var wasActive = false
        for step in 0..<4800 {
            let time = Double(step) * 0.5  // 40-minute sweep
            let vessel = SkyMath.vessel(time: time)
            #expect(vessel == SkyMath.vessel(time: time))
            if let vessel {
                activeSamples += 1
                if !wasActive { appearances += 1 }
                wasActive = true
                #expect((0.0...1.0).contains(vessel.progress))
                #expect((0.05...0.4).contains(vessel.y))
                #expect(vessel.brightness >= 0 && vessel.brightness <= 1)
            } else {
                wasActive = false
            }
        }
        #expect(Double(activeSamples) / 4800.0 < 0.12)
        #expect(appearances >= 3)
        #expect(appearances <= 14)
    }
}

@Suite("SkyMath celestial")
struct SkyMathCelestialTests {

    @Test("the moon shines at night, hides at midday, and eases at the boundaries")
    func moonSchedule() {
        let midnight = SkyMath.celestial(dayFraction: 0.0)
        #expect(midnight.brightness > 0.7)
        let noon = SkyMath.celestial(dayFraction: 0.5)
        #expect(noon.brightness == 0)
        #expect(SkyMath.celestial(dayFraction: 0.795).brightness < 0.3)  // just after dusk: easing in
        #expect(SkyMath.celestial(dayFraction: 0.285).brightness < 0.3)  // just before dawn: easing out
    }

    @Test("the moon arcs across the upper sky through the night")
    func moonArc() {
        var previousX: Double?
        for fraction in [0.80, 0.90, 0.99, 0.07, 0.20, 0.28] {
            let moon = SkyMath.celestial(dayFraction: fraction)
            #expect(moon == SkyMath.celestial(dayFraction: fraction))
            if moon.brightness > 0 {
                #expect((0.1...0.9).contains(moon.x))
                #expect((0.03...0.35).contains(moon.y))
                if let previousX { #expect(moon.x > previousX) }  // steadily crosses
                previousX = moon.x
            }
        }
    }

    @Test("the horizon warms at dawn and dusk, not at midnight or midday")
    func dawnDuskWarmth() {
        let dawn = SkyMath.celestial(dayFraction: 0.27).glowBoost
        let dusk = SkyMath.celestial(dayFraction: 0.81).glowBoost
        let midnight = SkyMath.celestial(dayFraction: 0.0).glowBoost
        let noon = SkyMath.celestial(dayFraction: 0.5).glowBoost
        #expect(dawn > 0.1 && dusk > 0.1)
        #expect(dawn > midnight && dusk > noon)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let boost = SkyMath.celestial(dayFraction: fraction).glowBoost
            #expect(boost >= 0 && boost <= 0.35)
        }
    }
}

@Suite("SkyMath constellations")
struct SkyMathConstellationTests {

    @Test("constellations appear rarely, hold a moment, and stay in the upper sky")
    func constellationsRareAndBounded() {
        var activeSamples = 0
        var appearances = 0
        var wasActive = false
        for step in 0..<4800 {
            let time = Double(step) * 0.5  // 40-minute sweep
            let constellation = SkyMath.constellation(time: time)
            #expect(constellation == SkyMath.constellation(time: time))
            if let constellation {
                activeSamples += 1
                if !wasActive { appearances += 1 }
                wasActive = true
                #expect((4...6).contains(constellation.points.count))
                #expect(constellation.brightness >= 0 && constellation.brightness <= 1)
                for point in constellation.points {
                    #expect((0.0...1.0).contains(point.x))
                    #expect((0.0...0.5).contains(point.y))  // upper sky only
                }
            } else {
                wasActive = false
            }
        }
        #expect(Double(activeSamples) / 4800.0 < 0.15)
        #expect(appearances >= 4)
        #expect(appearances <= 20)
    }
}

@Suite("SkyMath shooting stars")
struct SkyMathShootingStarTests {

    @Test("streaks come every ten-or-so seconds, sometimes together, always valid")
    func frequentAndBounded() {
        var activeSamples = 0
        var appearances = 0
        var wasActive = false
        var sawConcurrent = false
        for step in 0..<24000 {
            let time = Double(step) * 0.05  // 1200 s at 20 Hz
            let streaks = SkyMath.shootingStars(time: time)
            #expect(streaks == SkyMath.shootingStars(time: time))
            #expect(streaks.count <= 3)
            if streaks.count > 1 { sawConcurrent = true }
            if streaks.isEmpty {
                wasActive = false
            } else {
                activeSamples += 1
                if !wasActive { appearances += 1 }
                wasActive = true
                for streak in streaks {
                    #expect((0.0...1.0).contains(streak.progress))
                    #expect(streak.brightness >= 0 && streak.brightness <= 1)
                    #expect((0.0...1.0).contains(streak.startX))
                    #expect((0.0...0.5).contains(streak.startY))  // upper sky only
                }
            }
        }
        #expect(Double(activeSamples) / 24000.0 < 0.15)  // frequent, still calm
        #expect(appearances >= 40)  // far beyond once a minute
        #expect(appearances <= 130)
        #expect(sawConcurrent)  // two sometimes cross together
    }
}
