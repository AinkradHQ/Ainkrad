import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Applies the Motion & Sound step's choices to the live stores.
///
/// `SkySettingsStore.setMotionSpeed` clamps to `speedRange` (0.5...1.5);
/// `GeneralSettingsStore.setSoundVolume` does not clamp, so the view must not
/// offer a value outside 0...1.
@MainActor
enum SetupMotionSound {
    static func apply(
        reduceMotion: Bool, skyMotion: Bool, skySpeed: Double,
        soundEnabled: Bool, volume: Double,
        general: GeneralSettingsStore, sky: SkySettingsStore
    ) {
        general.setUiReduceMotion(reduceMotion)
        sky.setMotionEnabled(skyMotion)
        sky.setMotionSpeed(skySpeed)
        general.setSoundEnabled(soundEnabled)
        general.setSoundVolume(volume)
    }
}

/// The Motion & Sound step: reduce-motion, the living sky, and sound effects,
/// each applying immediately to the live `GeneralSettingsStore` /
/// `SkySettingsStore`.
///
/// ART DIRECTION — the sky is the subject, so the sky is not described.
///
/// The living sky is rendering behind the blur while this screen is up. The
/// earlier pass wrote a paragraph explaining what the sky does ("freezes every
/// ambient effect in place…") next to a switch, which is a label describing
/// something the user can already see. This version points at it instead: the
/// copy says *look up there*, and the switch's own text is short, because the
/// screen behind it is the explanation.
///
/// REDUCE MOTION keeps its prominence, and gains more of it. It leads the
/// screen, above the sky and sound, in a tinted panel that is visibly a
/// different kind of thing from the two switches under it — not because it is
/// an error, but because it is the one setting here whose default is wrong for
/// some people in a way they feel immediately (vestibular discomfort from the
/// parallax sky and animated islands), and first-run is the only moment the app
/// will ever ask. Its copy names *why* it exists, and — the part that makes it
/// believable — promises the proof the very next screen delivers: turn it on
/// and the rest of the wizard stops moving.
///
/// That promise is load-bearing, so the seam behind it is real:
/// `GeneralSettingsStore` is `@Observable`, `AinkradApp` injects
/// `\.ainkradReduceMotion` from `uiReduceMotion`, and every animation in the
/// wizard reads it through `SetupStageMotion`. Flipping this toggle re-renders
/// the host root and the next Continue is a hard cut. `SetupStageTests` pins
/// the policy; `SetupMotionSoundReduceMotionSeamTests` pins the wiring.
///
/// SPEED reconciled with Settings: this step used to carry a continuous
/// tortoise→hare slider where Settings → Living Sky carries a Calm/Normal/
/// Lively segmented picker — the same setting wearing two faces. Both now
/// render `SkySettingsStore.speedPresets`, defined once on the store.
///
/// Sky effects: the wizard exposes only the master switch and the speed, not
/// the 14 individual `SkyEffect` toggles — those stay a Settings → Living Sky
/// concern. Surfacing all 14 here would turn a first-run pass into a control
/// panel; a curated subset would be a second, incomplete copy of a list
/// Settings already renders in full.
///
/// `SetupMotionSound.apply` exists for the applier test, not for this view:
/// each control fires its own store setter directly, the same
/// apply-immediately-and-independently model `SetupAppearanceStepView` uses.
struct SetupMotionSoundStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.setupGroupWidth) private var groupWidth
    @Environment(\.ainkradSkin) private var skin

    let coordinator: SetupCoordinator

    /// Flipped once on appear to stage the sections in. Never reset — coming
    /// Back to this step re-mounts the view.
    @State private var hasSettled = false

    var body: some View {
        let tokens = environment.themeManager.hostSkin

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s22) {
                    reduceMotionPanel(tokens: tokens)
                    skySection(tokens: tokens)
                    soundSection(tokens: tokens)
                }
                .padding(skin.size.s20)
                // FILLS the group, exactly as the Home step's folder listing
                // does. Capping the whole column instead left every panel hard
                // against the left edge with a void beside it — the layout read
                // as broken rather than as composed, because the empty space was
                // INSIDE the group rather than around it.
                //
                // Prose within the column is capped individually; see the
                // section hints.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { hasSettled = true }

            // Never blocking, for the same reason as Appearance: every control
            // has a real default already applied live.
            SetupStepFooter(coordinator: coordinator) { coordinator.advance() }
        }
    }

    // MARK: - Reduce motion (leads the screen — see the type doc)

    /// Deliberately unlike the two rows below it: tinted, roomier, its title set
    /// at the size the other sections use for their headings, and its own
    /// sentence rather than a subtitle. It is the question this screen exists to
    /// ask; the sky and sound switches are the follow-ups.
    private func reduceMotionPanel(tokens: AinkradSkin) -> some View {
        let store = environment.generalSettingsStore
        return staged(index: 0) {
            HStack(alignment: .top, spacing: skin.size.s14) {
                VStack(alignment: .leading, spacing: skin.size.s7) {
                    // Names the STATE the switch produces when it is on, not an
                    // instruction. "Turn the motion off" shipped first and read
                    // well as prose and badly as a control: on meant off. It is
                    // also the exact name Settings → Appearance uses, and the
                    // one VoiceOver already announced — so sighted and
                    // screen-reader users now hear the same word.
                    Text("Reduce motion")
                        .font(AinkradFont.display(16, weight: .medium))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o95))
                    Text(
                        "Ainkrad drifts, parallaxes and springs by default. If that kind of "
                            + "movement makes you queasy, turn this on — the rest of this setup "
                            + "will stop animating on the very next screen, so you can see it "
                            + "worked. This is the only time Ainkrad asks; it lives in "
                            + "Settings → Appearance afterwards."
                    )
                    .font(AinkradFont.display(13))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o72))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    // Prose is capped even though the column fills — see the
                    // column's own comment.
                    .frame(
                        maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                        alignment: .leading
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                AinkradToggle(
                    isOn: Binding(
                        get: { store.uiReduceMotion },
                        set: { store.setUiReduceMotion($0) })
                )
                .accessibilityLabel("Reduce motion")
            }
            .padding(skin.spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Tint, no border and no rule — the emphasis is the surface itself,
            // per the no-separator design language.
            .background(
                ChamferShape(cut: skin.radius.md)
                    .fill(tokens.color(\.accentPrimary).opacity(skin.opacity.o10))
            )
            .accessibilityIdentifier("setup.motion.reduceMotion")
        }
    }

    // MARK: - Living sky

    private func skySection(tokens: AinkradSkin) -> some View {
        let store = environment.skySettingsStore
        return staged(index: 1) {
            VStack(alignment: .leading, spacing: skin.spacing.md) {
                // Points at the window, not at the switch. The sentence is the
                // only place the sky gets described, and it describes where to
                // look rather than what it does.
                sectionIntro(
                    title: "The sky behind this",
                    hint: "That is it, live, right now. Switch it off and the scene "
                        + "stays exactly where it is — everything in it just stops.",
                    tokens: tokens)
                toggleRow(
                    tokens: tokens,
                    title: "Animate the sky",
                    isOn: store.motionEnabled,
                    action: { store.setMotionEnabled($0) }
                )
                if store.motionEnabled {
                    speedRow(tokens: tokens, store: store)
                }
            }
        }
    }

    /// The same Calm/Normal/Lively picker Settings → Living Sky renders, off
    /// the same `SkySettingsStore.speedPresets`. Every preset is inside
    /// `speedRange`, so the clamp in `setMotionSpeed` never fires from here.
    private func speedRow(tokens: AinkradSkin, store: SkySettingsStore) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            Text("How fast")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
            AinkradSegmentedPicker(
                items: SkySettingsStore.speedPresets.map(\.value),
                selection: Binding(
                    get: { SkySettingsStore.nearestPreset(to: store.motionSpeed) },
                    set: { store.setMotionSpeed($0) }
                ),
                label: { SkySettingsStore.presetTitle($0) }
            )
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: skin.radius.md).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o45)))
    }

    // MARK: - Sound

    private func soundSection(tokens: AinkradSkin) -> some View {
        let store = environment.generalSettingsStore
        return staged(index: 2) {
            VStack(alignment: .leading, spacing: skin.spacing.md) {
                sectionIntro(
                    title: "Sound",
                    hint: "Short cues when something opens, closes, or finishes. "
                        + "Nothing that plays while you are reading.",
                    tokens: tokens)
                toggleRow(
                    tokens: tokens,
                    title: "Sound effects",
                    isOn: store.soundEnabled,
                    action: { store.setSoundEnabled($0) }
                )
                if store.soundEnabled {
                    volumeRow(tokens: tokens, store: store)
                }
            }
        }
    }

    private func volumeRow(tokens: AinkradSkin, store: GeneralSettingsStore) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            Text("Volume")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
            HStack(spacing: skin.size.s10) {
                Image(systemName: "speaker.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
                // Bounded to 0...1 in the view: `setSoundVolume` does not clamp,
                // so `AinkradSlider`'s own `in:` range is what keeps this safe.
                // Same range as the Sound & Voice page's volume row.
                AinkradSlider(
                    value: Binding(
                        get: { store.soundVolume },
                        set: { store.setSoundVolume($0) }
                    ),
                    in: 0...1
                )
                Image(systemName: "speaker.wave.3.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
            }
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: skin.radius.md).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o45)))
    }

    // MARK: - Shared pieces

    /// A spoken heading and one sentence, replacing the all-caps section
    /// headers this step used to carry. Same shape as the Appearance step's
    /// groups, so the two live-preview screens read as a pair.
    private func sectionIntro(title: String, hint: String, tokens: AinkradSkin) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s5) {
            Text(title)
                .font(AinkradFont.display(15, weight: .medium))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o95))
            Text(hint)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o55))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The switch rows carry a title only. Their explanation is in the intro
    /// above them, and — for the sky — in the window behind them.
    private func toggleRow(
        tokens: AinkradSkin, title: String,
        isOn: Bool, action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: skin.spacing.md) {
            Text(title)
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
            Spacer(minLength: skin.spacing.md)
            AinkradToggle(isOn: Binding(get: { isOn }, set: action))
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: skin.radius.md).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o45)))
    }

    /// Staging, routed through `SetupStageMotion` — never a bare
    /// `.animation(...)`. Under reduce-motion the geometry and the animation are
    /// both `nil`, so the sections are simply present. That matters more here
    /// than anywhere else in the wizard: a user who turns reduce-motion on and
    /// then walks Back to this screen must not be met by the thing they just
    /// switched off.
    private func staged<Content: View>(
        index: Int,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let geometry = SetupStageMotion.layerGeometry(
            .content,
            reduceMotion: reduceMotion,
            isForward: true)
        let lift = geometry.map { $0.lift * 0.6 } ?? 0
        // ONLY the per-index stagger. `SetupStageMotion.animation(layer:)`
        // already carries the layer's own delay (0.11s for `.content`), so
        // adding `geometry.delay` on top of it — as the first version of this
        // did — made every section wait 0.22s before anything appeared at all,
        // which reads as lag rather than composition. `geometry` is still what
        // is consulted, because `nil` is the reduce-motion seam.
        let delay = geometry.map { _ in Double(index) * 0.06 } ?? 0

        return content()
            .opacity(hasSettled ? 1 : 0)
            .offset(y: hasSettled ? 0 : lift)
            .animation(
                SetupStageMotion.animation(
                    reduceMotion: reduceMotion,
                    layer: .content)?.delay(delay),
                value: hasSettled)
    }
}
