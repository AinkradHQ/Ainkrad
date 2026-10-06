// design-lint: allow-file opacity-literal token-gap colors.sky — the sky's colour data (per-effect alphas)
import AinkradAppKitUI
import AinkradHostRuntime
import AppKit
import SwiftUI

extension Color {
    /// Linear blend in sRGB toward `other` (`t` clamped to 0…1). Used to
    /// sweep smoothly between theme accents so multi-hue gradients stay soft —
    /// abrupt hue switches between adjacent samples read as luminance ridges.
    func blended(with other: Color, amount t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .clear
        let f = CGFloat(min(max(t, 0), 1))
        return Color(
            .sRGB,
            red: Double(a.redComponent + (b.redComponent - a.redComponent) * f),
            green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * f),
            blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * f)
        )
    }
}

/// Scry drawing for every layer of the ambient sky. Pure functions of
/// (time, size, tokens) — all motion math lives in `SkyMath`, all gating in
/// `AmbientSkyView`. Kept apart from the view so each effect stays a small,
/// independently readable pass.
@MainActor
enum SkyRenderer {

    // MARK: Aurora

    /// Two vast, ultra-soft ribbons of accent light. Each segment is a
    /// screen-blended radial gradient squashed into a band; overlapping
    /// segments merge into one continuous, shimmering curtain. `surge`
    /// (0…1, from `SkyMath.auroraSurge`) blooms the whole curtain briefly.
    static func aurora(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        surge: Double, intensity: Double = 1, tokens: AinkradSkin
    ) {
        // Sweep smoothly through all three theme accents across the curtain
        // so it reads as this theme's full palette. A *smooth* sweep (not a
        // per-segment hue switch) keeps adjacent samples close in luminance,
        // so the screen-blended ribbon stays band-free (SkyRendererTests).
        let accents = [tokens.color(\.accentPrimary), tokens.color(\.accentSecondary), tokens.color(\.accentTertiary)]
        func auroraHue(ribbon: Int, segment: Int) -> Color {
            let phase =
                Double(segment) / Double(SkyMath.auroraSegments) * Double(accents.count)
                + Double(ribbon)
            let base = Int(phase.rounded(.down)) % accents.count
            let next = (base + 1) % accents.count
            return accents[base].blended(with: accents[next], amount: phase - phase.rounded(.down))
        }
        for ribbon in 0..<SkyMath.auroraRibbons {
            for segment in 0..<SkyMath.auroraSegments {
                let color = auroraHue(ribbon: ribbon, segment: segment)
                let blob = SkyMath.auroraSegment(ribbon: ribbon, segment: segment, time: time)
                let radiusX = blob.radiusX * size.width
                let radiusY = blob.radiusY * size.width
                let opacity = blob.opacity * (1 + surge * 0.8) * intensity

                var layer = context
                layer.blendMode = .screen
                layer.translateBy(x: blob.x * size.width, y: blob.y * size.height)
                layer.scaleBy(x: 1, y: radiusY / radiusX)
                layer.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: -radiusX, y: -radiusX,
                            width: radiusX * 2, height: radiusX * 2)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                        center: .zero, startRadius: 0, endRadius: radiusX
                    )
                )
            }
        }
    }

    // MARK: Stars

    /// The endlessly drifting starfield: twinkle always, glints only while
    /// animated (`time > 0`).
    static func stars(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        intensity: Double = 1, tokens: AinkradSkin
    ) {
        for index in 0..<SkyMath.starCount {
            let star = SkyMath.star(index: index)
            let position = SkyMath.position(index: index, time: time)
            let x = position.x * size.width
            let y = position.y * size.height

            let glint = time > 0 ? SkyMath.glint(index: index, time: time) : 0
            // Weather sharpens or softens the whole field.
            let brightness = min(
                (star.baseOpacity * SkyMath.twinkle(index: index, time: time) + glint * 0.45) * intensity,
                0.9
            )

            let radius = star.radius * (1 + glint * 0.8)
            let color = (star.isAccent ? tokens.color(\.accentSecondary) : tokens.color(\.foreground))
                .opacity(brightness)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            if glint > 0 {
                // Soft halo while a star glints.
                context.fill(
                    Path(ellipseIn: rect.insetBy(dx: -radius * 1.6, dy: -radius * 1.6)),
                    with: .color(color.opacity(0.25))
                )
            }
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    // MARK: Streaks (shooting stars, meteor showers, the comet)

    /// One streak. `comet: true` draws the slow crossing — longer tail,
    /// wider glow, and a bright head.
    static func streak(
        _ streak: SkyMath.ShootingStar,
        in context: inout GraphicsContext, size: CGSize, comet: Bool, tokens: AinkradSkin
    ) {
        let inclination = abs(streak.angle)
        let direction = CGVector(
            dx: (streak.angle >= 0 ? 1 : -1) * cos(inclination),
            dy: sin(inclination)  // always descending
        )
        let travel = size.width * (comet ? 0.55 : 0.22)
        let length = size.width * (comet ? 0.16 : 0.10)
        let head = CGPoint(
            x: streak.startX * size.width + direction.dx * travel * streak.progress,
            y: streak.startY * size.height + direction.dy * travel * streak.progress
        )
        let tail = CGPoint(x: head.x - direction.dx * length, y: head.y - direction.dy * length)

        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)

        // Wide soft glow beneath a bright core that fades along its tail.
        context.stroke(
            path,
            with: .color(tokens.color(\.accentPrimary).opacity((comet ? 0.35 : 0.25) * streak.brightness)),
            lineWidth: comet ? 6 : 3.5
        )
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    tokens.color(\.accentPrimary).opacity(0),
                    tokens.color(\.foreground).opacity(0.85 * streak.brightness),
                ]),
                startPoint: tail,
                endPoint: head
            ),
            lineWidth: comet ? 1.8 : 1.4
        )
        if comet {
            let headRadius = 2.6
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: head.x - headRadius, y: head.y - headRadius,
                        width: headRadius * 2, height: headRadius * 2)),
                with: .color(tokens.color(\.foreground).opacity(0.9 * streak.brightness))
            )
        }
    }

    // MARK: Atmosphere

    /// Faint fog bands sliding sideways near the horizon.
    static func mist(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        intensity: Double = 1, tokens: AinkradSkin
    ) {
        for index in 0..<SkyMath.mistBands {
            let band = SkyMath.mistBand(index: index, time: time)
            let radiusX = band.radiusX * size.width
            let radiusY = band.radiusY * size.width

            var layer = context
            layer.blendMode = .screen
            layer.translateBy(x: band.x * size.width, y: band.y * size.height)
            layer.scaleBy(x: 1, y: radiusY / radiusX)
            layer.fill(
                Path(
                    ellipseIn: CGRect(
                        x: -radiusX, y: -radiusX,
                        width: radiusX * 2, height: radiusX * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        tokens.color(\.foreground).opacity(band.opacity * intensity), tokens.color(\.foreground).opacity(0),
                    ]),
                    center: .zero, startRadius: 0, endRadius: radiusX
                )
            )
        }
    }

    /// Soft god-rays fanning up from the below-horizon sun (the same point
    /// the horizon glow radiates from), swaying almost imperceptibly. Each
    /// beam is an elongated elliptical radial gradient — soft along AND
    /// across, so no edge can ever band. (The original hard-sided gradient
    /// rectangles drew visible slabs; SkyRendererTests guards this.)
    /// `emphasis` (per-theme, see `SkyProfile`) scales the beams' strength.
    static func lightRays(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        emphasis: Double = 1, tokens: AinkradSkin
    ) {
        let sun = CGPoint(x: size.width * 0.5, y: size.height * 1.15)
        // Each beam carries a different theme accent so the fan reads as this
        // theme's hues rather than one flat accent; they overlap softly near
        // the sun under `.screen` and merge.
        let accents = [tokens.color(\.accentPrimary), tokens.color(\.accentSecondary), tokens.color(\.accentTertiary)]
        for index in 0..<SkyMath.lightRayCount {
            let ray = SkyMath.lightRay(index: index, time: time)
            let color = accents[index % accents.count]
            let along = size.height * 0.45  // beam half-length
            let across = ray.width * size.width * 0.7  // beam half-width
            // Up-sky unit vector for this beam's tilt (y grows downward).
            let direction = CGVector(dx: sin(ray.angle), dy: -cos(ray.angle))
            let mid = CGPoint(
                x: sun.x + direction.dx * along * 1.1,
                y: sun.y + direction.dy * along * 1.1
            )

            var layer = context
            layer.blendMode = .screen
            layer.translateBy(x: mid.x, y: mid.y)
            layer.rotate(by: .radians(ray.angle))
            layer.scaleBy(x: across / along, y: 1)
            layer.fill(
                Path(ellipseIn: CGRect(x: -along, y: -along, width: along * 2, height: along * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(ray.opacity * emphasis), color.opacity(0)]),
                    center: .zero, startRadius: 0, endRadius: along
                )
            )
        }
    }

    // MARK: Fireflies and bokeh

    /// Accent energy motes rising through the island's region, each with a
    /// soft halo. They carry `accentTertiary` — the theme's third accent,
    /// unused elsewhere — so each theme's fireflies read as its own hue.
    /// `emphasis` (per-theme, see `SkyProfile`) scales their presence.
    static func fireflies(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        emphasis: Double = 1, tokens: AinkradSkin
    ) {
        for index in 0..<SkyMath.fireflyCount {
            let fly = SkyMath.firefly(index: index, time: time)
            guard fly.opacity > 0.005 else { continue }
            let x = fly.x * size.width
            let y = fly.y * size.height
            let color = tokens.color(\.accentTertiary)
            let opacity = fly.opacity * emphasis

            let halo = fly.radius * 2.4
            context.fill(
                Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                with: .color(color.opacity(opacity * 0.3))
            )
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: x - fly.radius, y: y - fly.radius,
                        width: fly.radius * 2, height: fly.radius * 2)),
                with: .color(color.opacity(opacity))
            )
        }
    }

    /// Large, ultra-faint out-of-focus orbs in the extreme foreground —
    /// drawn last, over everything in the sky.
    static func bokeh(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: AinkradSkin
    ) {
        for index in 0..<SkyMath.bokehCount {
            let orb = SkyMath.bokehOrb(index: index, time: time)
            let radius = orb.radius * size.width
            // Three-way cycle so the theme's third accent shows in the
            // foreground orbs alongside foreground and the primary accent.
            let color: Color
            switch index % 3 {
            case 0: color = tokens.color(\.foreground)
            case 1: color = tokens.color(\.accentPrimary)
            default: color = tokens.color(\.accentTertiary)
            }

            var layer = context
            layer.blendMode = .screen
            layer.fill(
                Path(
                    ellipseIn: CGRect(
                        x: orb.x * size.width - radius, y: orb.y * size.height - radius,
                        width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(orb.opacity), color.opacity(0)]),
                    center: CGPoint(x: orb.x * size.width, y: orb.y * size.height),
                    startRadius: 0, endRadius: radius
                )
            )
        }
    }

    // MARK: Moon

    /// A soft crescent high in the night sky — a glowing orb with an offset
    /// punch-out, wrapped in a wide halo. Crisp by design, like the stars.
    static func moon(
        _ celestial: SkyMath.Celestial,
        in context: inout GraphicsContext, size: CGSize, tokens: AinkradSkin
    ) {
        guard celestial.brightness > 0.01 else { return }
        let center = CGPoint(x: celestial.x * size.width, y: celestial.y * size.height)
        let radius = size.width * 0.016

        var halo = context
        halo.blendMode = .screen
        let haloRadius = radius * 3.4
        halo.fill(
            Path(
                ellipseIn: CGRect(
                    x: center.x - haloRadius, y: center.y - haloRadius,
                    width: haloRadius * 2, height: haloRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    tokens.color(\.foreground).opacity(0.16 * celestial.brightness),
                    tokens.color(\.foreground).opacity(0),
                ]),
                center: center, startRadius: 0, endRadius: haloRadius
            )
        )

        context.drawLayer { body in
            body.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2)),
                with: .color(tokens.color(\.foreground).opacity(0.5 * celestial.brightness))
            )
            body.blendMode = .destinationOut
            let punch = CGPoint(x: center.x + radius * 0.5, y: center.y - radius * 0.28)
            body.fill(
                Path(
                    ellipseIn: CGRect(
                        x: punch.x - radius, y: punch.y - radius,
                        width: radius * 2, height: radius * 2)),
                with: .color(.black)
            )
        }
    }

    // MARK: Sky traffic

    /// A distant vessel crossing the high sky: a faint elongated glow, a
    /// bright hull speck, and a blinking accent beacon.
    static func vessel(
        _ vessel: SkyMath.Vessel,
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval, tokens: AinkradSkin
    ) {
        let x =
            (vessel.direction > 0
                ? -0.04 + 1.08 * vessel.progress
                : 1.04 - 1.08 * vessel.progress) * size.width
        let y = vessel.y * size.height + sin(vessel.progress * 4 * .pi) * 2

        var glow = context
        glow.blendMode = .screen
        glow.translateBy(x: x, y: y)
        glow.scaleBy(x: 1, y: 0.35)
        glow.fill(
            Path(ellipseIn: CGRect(x: -11, y: -11, width: 22, height: 22)),
            with: .radialGradient(
                Gradient(colors: [
                    tokens.color(\.accentPrimary).opacity(0.35 * vessel.brightness),
                    tokens.color(\.accentPrimary).opacity(0),
                ]),
                center: .zero, startRadius: 0, endRadius: 11
            )
        )

        context.fill(
            Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)),
            with: .color(tokens.color(\.foreground).opacity(0.7 * vessel.brightness))
        )
        let blink = sin(time * 2 * .pi * 0.9) > 0.55 ? 1.0 : 0.15
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: x + 4 * vessel.direction - 0.9, y: y - 0.9,
                    width: 1.8, height: 1.8)),
            with: .color(tokens.color(\.accentSecondary).opacity(0.9 * vessel.brightness * blink))
        )
    }

    // MARK: Constellations

    /// A handful of neighboring stars brighten while faint lines trace
    /// between them, then the whole figure dissolves.
    static func constellation(
        _ constellation: SkyMath.Constellation,
        in context: inout GraphicsContext, size: CGSize, tokens: AinkradSkin
    ) {
        let points = constellation.points.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        guard let first = points.first else { return }

        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(
            path,
            with: .color(tokens.color(\.accentSecondary).opacity(0.28 * constellation.brightness)),
            lineWidth: 0.8
        )

        for point in points {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                with: .color(tokens.color(\.accentSecondary).opacity(0.16 * constellation.brightness))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 1.6, y: point.y - 1.6, width: 3.2, height: 3.2)),
                with: .color(tokens.color(\.foreground).opacity(0.85 * constellation.brightness))
            )
        }
    }

    // MARK: Embers

    /// ~70 embers, deterministically placed from their index, drifting
    /// upward and twinkling. `emphasis` (per-theme, see `SkyProfile`) scales
    /// their glow — warm themes push it up, cool themes pull it back.
    static func embers(
        in context: inout GraphicsContext, size: CGSize, time: TimeInterval,
        emphasis: Double = 1, tokens: AinkradSkin
    ) {
        for index in 0..<SkyMath.emberCount {
            let ember = SkyMath.ember(index: index, time: time)
            let x = ember.x * size.width
            let y = ember.y * size.height
            let color = (ember.isAccent ? tokens.color(\.accentSecondary) : tokens.color(\.foreground))
                .opacity(ember.opacity * emphasis)
            let rect = CGRect(
                x: x - ember.radius, y: y - ember.radius,
                width: ember.radius * 2, height: ember.radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
