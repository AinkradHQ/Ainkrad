import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Accumulates virtual sky-time as the integral of the user's speed setting,
/// so changing speed ramps the motion smoothly instead of teleporting the
/// whole field (which `wallClock × speed` would do). Plain class on purpose:
/// mutating it per frame must never re-invalidate SwiftUI.
@MainActor
final class SkyClock {
    private var lastReal: Double?
    private var virtual: Double = 0

    func tick(real: Double, speed: Double) -> Double {
        virtual += max(0, real - (lastReal ?? real)) * speed
        lastReal = real
        return virtual
    }

    /// Back to the frozen arrangement's zero. Called when animation stops,
    /// so re-enabling resumes smoothly from exactly the pose the user was
    /// looking at instead of jump-cutting across the paused span.
    func reset() {
        lastReal = nil
        virtual = 0
    }
}

/// The OS "sky": an atmospheric, theme-driven backdrop behind every
/// workspace — deep vertical gradient, breathing horizon glow, aurora
/// ribbons, a drifting starfield, god-rays, horizon mist, fireflies, rising
/// embers, foreground bokeh, and rare sky events. Every effect is
/// individually switchable in Settings → Living Sky (`SkySettingsStore`),
/// with a master animate switch and speed control.
///
/// Deliberately game-like ambience rather than a flat app background. The
/// app's own "Animate the sky" switch is the single authority here — by
/// explicit product decision it does NOT follow macOS Reduce Motion, so the
/// scene stays alive regardless of the system setting; users who want it
/// still have the in-app switch.
struct AmbientSkyView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradMotionBudget) private var motionBudget

    @State private var clock = SkyClock()

    /// Whether this instance animates.
    ///
    /// `true` for the one real sky behind the workspace — that motion is the
    /// product, and the "Animate the sky" switch is its only authority.
    ///
    /// `false` for the *decorative copies*. A view cannot blur the layers
    /// behind it, so every translucent pane with blur enabled draws its own
    /// sky + island copy and blurs that (`BlockView`). Those copies were fully
    /// live: N blurred panes meant N extra 30fps scenes, each ~570 Scry
    /// fills and 18 radial gradients — by a wide margin the most expensive
    /// thing the app did, and all of it under a 26pt Gaussian blur where the
    /// motion is not perceptible. The frozen branch below already existed for
    /// the settings switch; this just lets a caller ask for it.
    var isLive: Bool = true

    var body: some View {
        let tokens = environment.themeManager.tokens
        // Per-theme sky character (emphasis only — colors come from `tokens`).
        // Read `currentTheme` (observed) so a theme switch repaints the sky.
        let profile = environment.themeManager.currentTheme.skyProfile
        let sky = environment.skySettingsStore
        let animated = sky.motionEnabled && isLive && motionBudget.isAnimating
        // Register the per-effect switches as a body-level dependency: most
        // reads happen inside the Scry renderer closure, which @Observable
        // doesn't track — without this line, toggles wouldn't repaint the
        // frozen sky.
        let _ = sky.effectEnabled

        ZStack {
            LinearGradient(
                stops: [
                    .init(color: tokens.background, location: 0),
                    .init(color: tokens.surface, location: 0.55),
                    .init(color: tokens.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if animated {
                TimelineView(.animation(minimumInterval: motionBudget.minimumInterval ?? 1.0 / 30.0)) { context in
                    layers(
                        at: clock.tick(
                            real: context.date.timeIntervalSinceReferenceDate,
                            speed: sky.motionSpeed
                        ),
                        sky: sky, tokens: tokens, profile: profile
                    )
                }
            } else {
                layers(at: 0, sky: sky, tokens: tokens, profile: profile)
            }
        }
        .ignoresSafeArea()
        .onChange(of: animated) { _, isAnimated in
            // The frozen branch shows the time-0 arrangement; rewind the
            // clock to match so re-enabling animates forward from that
            // exact pose rather than teleporting across the paused span.
            if !isAnimated { clock.reset() }
        }
    }

    /// Everything above the base gradient: the two glows (breathing when the
    /// effect is on), then the canvas of drawn effects. At `time == 0` (the
    /// frozen path) the glows sit exactly at their historical static values.
    ///
    /// The ZStack here is load-bearing: inside `TimelineView`, a bare view
    /// tuple lays out as an implicit VERTICAL stack — the glows and canvas
    /// become three hard-edged horizontal bands across the home screen.
    /// `SkyRendererTests.animatedStructureHasNoBands` guards this.
    private func layers(at time: TimeInterval, sky: SkySettingsStore, tokens: DesignTokens, profile: SkyProfile) -> some View {
        let breath = sky.isEnabled(.breathingSky) && time > 0 ? SkyMath.breath(time: time) : 0.5
        // The one deliberate wall-clock input: the moon and the dawn/dusk
        // horizon warmth follow real local time.
        let celestial = sky.isEnabled(.celestial)
            ? SkyMath.celestial(dayFraction: Self.currentDayFraction())
            : nil
        let glowBoost = celestial?.glowBoost ?? 0

        return ZStack {
            // Horizon glow — a sun below the edge of the island.
            RadialGradient(
                colors: [tokens.accentPrimary.opacity((0.16 + 0.12 * breath) * (1 + glowBoost)), .clear],
                center: .init(x: 0.5, y: 1.15),
                startRadius: 0,
                endRadius: 900
            )

            // High-altitude accent haze, offset so the two glows don't read
            // as symmetric.
            RadialGradient(
                colors: [tokens.accentSecondary.opacity((0.05 + 0.06 * breath) * (1 + glowBoost)), .clear],
                center: .init(x: 0.18, y: -0.1),
                startRadius: 0,
                endRadius: 700
            )

            canvas(at: time, sky: sky, celestial: celestial, tokens: tokens, profile: profile)
        }
    }

    /// Local time of day as 0…1 from midnight — the input to
    /// `SkyMath.celestial`.
    private static func currentDayFraction(now: Date = Date()) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let seconds = Double(components.hour ?? 0) * 3600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
        return seconds / 86400
    }

    /// One Scry pass, back to front. Each effect draws only while its
    /// switch is on; streaks and events need `time > 0` (they don't exist in
    /// the frozen arrangement).
    private func canvas(
        at time: TimeInterval, sky: SkySettingsStore,
        celestial: SkyMath.Celestial?, tokens: DesignTokens, profile: SkyProfile
    ) -> some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            // The weather mood gently rebalances stars/aurora/mist; 0.5 is
            // the neutral point where every multiplier is exactly 1.
            let mood = sky.isEnabled(.weather) && time > 0 ? SkyMath.weather(time: time) : 0.5

            if let celestial {
                SkyRenderer.moon(celestial, in: &context, size: size, tokens: tokens)
            }
            if sky.isEnabled(.aurora) {
                let surge = sky.isEnabled(.skyMoments) && time > 0 ? SkyMath.auroraSurge(time: time) : 0
                SkyRenderer.aurora(in: &context, size: size, time: time, surge: surge,
                                   intensity: (1.2 - 0.4 * mood) * profile.aurora, tokens: tokens)
            }
            if sky.isEnabled(.lightRays) {
                SkyRenderer.lightRays(in: &context, size: size, time: time,
                                      emphasis: profile.lightRays, tokens: tokens)
            }
            if sky.isEnabled(.stars) {
                SkyRenderer.stars(in: &context, size: size, time: time,
                                  intensity: 1.15 - 0.3 * mood, tokens: tokens)
            }
            if time > 0, sky.isEnabled(.constellations), let figure = SkyMath.constellation(time: time) {
                SkyRenderer.constellation(figure, in: &context, size: size, tokens: tokens)
            }
            if time > 0, sky.isEnabled(.shootingStars) {
                for streak in SkyMath.shootingStars(time: time) {
                    SkyRenderer.streak(streak, in: &context, size: size, comet: false, tokens: tokens)
                }
            }
            if time > 0, sky.isEnabled(.skyMoments) {
                for streak in SkyMath.meteorShower(time: time) {
                    SkyRenderer.streak(streak, in: &context, size: size, comet: false, tokens: tokens)
                }
                if let comet = SkyMath.comet(time: time) {
                    SkyRenderer.streak(comet, in: &context, size: size, comet: true, tokens: tokens)
                }
            }
            if time > 0, sky.isEnabled(.skyTraffic), let vessel = SkyMath.vessel(time: time) {
                SkyRenderer.vessel(vessel, in: &context, size: size, time: time, tokens: tokens)
            }
            if sky.isEnabled(.horizonMist) {
                SkyRenderer.mist(in: &context, size: size, time: time,
                                 intensity: (0.4 + 1.2 * mood) * profile.mist, tokens: tokens)
            }
            if sky.isEnabled(.fireflies) {
                SkyRenderer.fireflies(in: &context, size: size, time: time,
                                      emphasis: profile.fireflies, tokens: tokens)
            }
            if sky.isEnabled(.embers) {
                SkyRenderer.embers(in: &context, size: size, time: time,
                                   emphasis: profile.embers, tokens: tokens)
            }
            if sky.isEnabled(.bokeh) {
                SkyRenderer.bokeh(in: &context, size: size, time: time, tokens: tokens)
            }
        }
        .allowsHitTesting(false)
    }
}
