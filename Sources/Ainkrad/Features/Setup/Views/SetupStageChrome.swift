import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

// MARK: - Rail model

/// The progress rail's data, derived from the coordinator and nothing else.
///
/// Deliberately view-free and pure so it can be tested without SwiftUI, and
/// deliberately WITHOUT a "step n of m" counter. The counter is what jumped
/// confusingly ("3 of 8" → "2 of 7") when the step list shrinks at the vault
/// swap; a rail that shows only the steps actually owed removes the
/// contradiction rather than papering over it.
struct SetupRailModel {
    struct Item: Identifiable, Equatable {
        let step: SetupStep
        let title: String
        /// Exactly one item is current — the coordinator has exactly one `step`.
        let isCurrent: Bool
        /// True for steps already walked past. Never true for the current one:
        /// the user is still standing on it.
        let isComplete: Bool

        var id: String { step.rawValue }
    }

    let items: [Item]

    /// `@MainActor` only because `SetupCoordinator` is — the resulting value is
    /// plain data and travels anywhere.
    @MainActor
    init(coordinator: SetupCoordinator) {
        let steps = coordinator.steps
        let currentIndex = steps.firstIndex(of: coordinator.step) ?? 0
        items = steps.enumerated().map { index, step in
            Item(
                step: step,
                title: step.title,
                isCurrent: index == currentIndex,
                isComplete: index < currentIndex)
        }
    }
}

// MARK: - Composition policy

/// How big the step's content group is allowed to get, and therefore how much
/// of a large window is deliberately left empty.
///
/// The stage is full-bleed; the CONTENT is not, and the difference is the whole
/// of this type. The first full-bleed build let the step fill the window, which
/// on a 1728x1084 display put the headline in the top-left, the body under it,
/// and the step's only button about 1000pt down and 700pt across in the
/// bottom-right — three things that belong to each other, separated by more
/// empty scrim than any of them occupied. It was reported as "the buttons are
/// not appearing", and it stranded the user on step 1 of 8.
///
/// So: one bounded group, centred, with the empty space around it rather than
/// running through it. Pure arithmetic, kept out of the view so the bounds can
/// be asserted at window sizes nobody will hand-test.
enum SetupStageLayout {
    /// The widest the group ever gets.
    ///
    /// Raised from 680 after hand-testing on a 1728pt window: the group sat at
    /// its cap while the window grew around it, which read as a small card
    /// stranded in a large window rather than as a composed screen.
    ///
    /// Running text is NOT allowed to get this wide — each step caps its own
    /// prose at a readable measure — but the panels around it (the folder
    /// listing, the provider rows) use the room.
    static let maximumColumnWidth: CGFloat = 1100

    /// Tall enough for the densest step (Providers, with a failure state showing)
    /// without the group ever becoming a column of its own on a tall display.
    static let maximumGroupHeight: CGFloat = 900

    /// Never let the group collapse to nothing on an absurd proposal — a zero
    /// size is how content disappears rather than merely being cramped.
    static let minimumColumnWidth: CGFloat = 280
    static let minimumGroupHeight: CGFloat = 240

    /// The group grows more slowly than the window, so the margins widen as the
    /// window does — but it keeps growing across every size a person actually
    /// uses, rather than hitting a cap early and standing still.
    ///
    /// Affine rather than a plain share, because the two ends want different
    /// behaviour: a small window should give the group nearly all of itself
    /// (the constant dominates), while a large one should hold some margin back
    /// (the slope dominates). A single share cannot do both — at 0.86 a 720pt
    /// window is right but a 2000pt one has no margin, and at 0.55 the reverse.
    private static let widthSlope: CGFloat = 0.55
    private static let widthBase: CGFloat = 190
    private static let heightSlope: CGFloat = 0.62
    private static let heightBase: CGFloat = 120

    /// The size of the heading + content + footer group for a given stage size.
    ///
    /// Monotonic in both axes by construction — a non-decreasing affine term,
    /// clamped by constants — which is what stops the size from inverting at
    /// some window dimension nobody tried.
    static func group(fitting stage: CGSize) -> CGSize {
        CGSize(
            width: clamp(
                stage.width * widthSlope + widthBase,
                low: minimumColumnWidth, high: maximumColumnWidth),
            height: clamp(
                stage.height * heightSlope + heightBase,
                low: minimumGroupHeight, high: maximumGroupHeight))
    }

    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        min(high, max(low, value))
    }

    // MARK: - Measures within the group
    //
    // Widening the group created a problem it did not have at 680: steps that
    // simply filled it now run their text to 1100pt, which is unreadable. So a
    // step has TWO measures, and which one a piece of content gets depends on
    // what it is:
    //
    //   - PANELS fill the group. Folder listings, provider rows, theme cards —
    //     things read by scanning, which use whatever room there is.
    //   - PROSE takes `readingWidth`. Sentences are read by returning to a left
    //     edge, and past roughly 75 characters the eye loses the line.
    //
    // An earlier version capped the whole column at a "content width" instead.
    // That looked wrong for the same reason the original bug did: it put the
    // empty space INSIDE the group, leaving every panel hard against the left
    // edge with a void beside it. Panels now fill and only prose is held back,
    // which is what the Home step was already doing when it read correctly.

    /// The measure running text is held to — about 75 characters at the wizard's
    /// body size, whatever the window is doing.
    static func readingWidth(inGroupOf group: CGFloat) -> CGFloat {
        clamp(group * 0.62, low: 280, high: 680)
    }
}

// MARK: - Group width, passed down

private struct SetupGroupWidthKey: EnvironmentKey {
    /// Matches the group a mid-sized window produces, so a step rendered outside
    /// the stage (a preview, a test) still lays out sensibly.
    static let defaultValue: CGFloat = 700
}

extension EnvironmentValues {
    /// The width of the stage's content group, published by `SetupStage` so each
    /// step can size its own column against it rather than hardcoding a number
    /// that only looks right at one window size.
    var setupGroupWidth: CGFloat {
        get { self[SetupGroupWidthKey.self] }
        set { self[SetupGroupWidthKey.self] = newValue }
    }
}

// MARK: - Rail

/// The thin progress rail across the top of the stage.
///
/// Spatial, not numeric: one segment per owed step, the current one lit and
/// slightly taller, the walked-past ones filled, the rest recessed. No text —
/// VoiceOver gets the words instead, where they cost the visual design nothing.
struct SetupRail: View {
    let model: SetupRailModel
    let tokens: DesignTokens
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.items) { item in
                Capsule()
                    .fill(fill(for: item))
                    .frame(height: item.isCurrent ? 4 : 2)
                    .frame(maxWidth: .infinity)
                    // Explicit: SwiftUI does not reliably expose a decorative
                    // shape as an accessibility element, so without this the
                    // labels below never reach VoiceOver despite the
                    // `children: .contain` group.
                    .accessibilityElement()
                    .accessibilityLabel(
                        item.isCurrent
                            ? "Current step: \(item.title)"
                            : item.title)
            }
        }
        .frame(height: 4)
        .animation(
            SetupStageMotion.animation(reduceMotion: reduceMotion),
            value: model.items
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
    }

    private func fill(for item: SetupRailModel.Item) -> Color {
        if item.isCurrent { return tokens.accentPrimary }
        if item.isComplete { return tokens.accentSecondary.opacity(0.7) }
        return tokens.foreground.opacity(0.16)
    }
}

// MARK: - Header metrics

/// The header's fixed sizes, in their own non-generic type because `SetupStage`
/// is generic over its content and generic types cannot hold stored statics.
enum SetupHeader {
    /// The `matchedGeometryEffect` identity shared by the hero mark and the
    /// inline one. One constant, because two string literals that must match is
    /// a silent-failure waiting to happen: a typo here does not fail to build,
    /// it just stops the mark animating.
    static let markID = "setup.brand.mark"
    static let heroDiameter: CGFloat = 236
    static let headlineSize: CGFloat = 30
    /// The inline mark matches the headline's height, so the two read as one
    /// line rather than as an icon parked next to some text.
    static let inlineMarkHeight: CGFloat = 30
}

// MARK: - Stage

/// The full-bleed wizard container: rail at the top, the step's own heading and
/// content in the middle with room around them, and the step's nav row at the
/// bottom.
///
/// There is no panel. `.hudPanelChrome` is gone deliberately — the wizard now
/// lays out against the window, over the scrim, with the living island reading
/// through it. The scrim itself stays (`SetupOverlayView`), and it stays without
/// a tap gesture: this overlay is non-dismissible.
///
/// The nav row is not built here. Every step view already ends in the shared
/// `SetupStepFooter`, which owns that step's primary title, its disabled state
/// and its action; the stage gives the step the full height so that footer
/// lands at the bottom of the stage. Absorbing it rather than duplicating it is
/// what keeps ONE Back in the wizard.
struct SetupStage<Content: View>: View {
    let coordinator: SetupCoordinator
    let tokens: DesignTokens
    let reduceMotion: Bool
    @ViewBuilder let content: (SetupStep) -> Content

    /// The index the stage was LAST rendering. Updated in `onChange`, i.e. after
    /// the render that observed the step change — which is exactly why direction
    /// is computed from it in `body` rather than assigned there.
    ///
    /// An earlier version assigned `isForward` inside `onChange` and read it
    /// from `body`. `onChange` runs after the update that observed the change,
    /// so every transition was computed from the PREVIOUS direction and the
    /// first Back animated as a forward. Deriving it during body evaluation
    /// means the transition and the direction it depends on come from the same
    /// change.
    @State private var lastIndex = 0

    /// Ties the hero mark on Welcome to the inline mark beside every other
    /// step's heading, so ONE mark travels between the two arrangements instead
    /// of one disappearing while another fades in somewhere else.
    @Namespace private var markSpace

    private var currentIndex: Int {
        coordinator.steps.firstIndex(of: coordinator.step) ?? 0
    }

    /// Seeded forward: the first appearance has nowhere to have come back from.
    private var isForward: Bool {
        SetupStageMotion.isForward(from: lastIndex, to: currentIndex)
    }

    var body: some View {
        GeometryReader { proxy in
            let group = SetupStageLayout.group(fitting: proxy.size)

            VStack(spacing: 0) {
                SetupRail(
                    model: SetupRailModel(coordinator: coordinator),
                    tokens: tokens,
                    reduceMotion: reduceMotion
                )
                .padding(.horizontal, 34)
                .padding(.top, 22)

                // Symmetric spacers, not one greedy one: the group sits in the
                // optical centre of what is left below the rail. A single
                // `Spacer(minLength:)` above the content is what pinned the
                // group to the top and let the footer fall to the window's far
                // bottom edge.
                Spacer(minLength: 24)

                // ONE group. The heading, the step's controls and the step's
                // footer are bounded together and travel together, so the
                // primary button is never more than a glance from the text that
                // explains it — whatever the window is doing.
                VStack(alignment: .leading, spacing: 22) {
                    header
                    content(coordinator.step)
                        .frame(
                            maxWidth: .infinity, maxHeight: .infinity,
                            alignment: coordinator.step.usesHeroMark ? .top : .topLeading
                        )
                        .transition(
                            SetupStageMotion.layerTransition(
                                .content, reduceMotion: reduceMotion, isForward: isForward)
                        )
                        .id(coordinator.step)
                }
                .frame(width: group.width, height: group.height, alignment: .topLeading)
                .environment(\.setupGroupWidth, group.width)
                // Makes the step change an animated transaction at all; each
                // layer's own `.animation` (with its stagger delay) then wins for
                // that layer. `nil` under reduce-motion, so the whole thing snaps.
                .animation(
                    SetupStageMotion.animation(reduceMotion: reduceMotion),
                    value: coordinator.step)

                Spacer(minLength: 24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Only ever CATCHES UP; it never decides the direction. `body` has
        // already rendered this change using the old value, which is the point.
        .onChange(of: coordinator.step) { _, newValue in
            lastIndex = coordinator.steps.firstIndex(of: newValue) ?? 0
        }
        .onAppear {
            lastIndex = currentIndex
        }
    }

    /// The mark and the headline, in one of two arrangements.
    ///
    /// On Welcome the mark is the subject: large and centred, with the headline
    /// beneath it. Everywhere else it shrinks to the headline's own height and
    /// sits inline before the words. Both branches carry the same
    /// `matchedGeometryEffect` identity, which is what makes leaving Welcome
    /// animate the mark from one to the other rather than cross-fading two
    /// unrelated views.
    ///
    /// The headline keeps its own layer and its own entry, ahead of the
    /// controls: one idea per screen, stated large.
    @ViewBuilder
    private var header: some View {
        if coordinator.step.usesHeroMark {
            VStack(spacing: 26) {
                SetupBrandMark(
                    tokens: tokens,
                    reduceMotion: reduceMotion,
                    style: .hero(diameter: SetupHeader.heroDiameter)
                )
                .matchedGeometryEffect(id: SetupHeader.markID, in: markSpace)
                headlineText
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 13) {
                SetupBrandMark(
                    tokens: tokens,
                    reduceMotion: reduceMotion,
                    style: .inline(height: SetupHeader.inlineMarkHeight)
                )
                .matchedGeometryEffect(id: SetupHeader.markID, in: markSpace)
                // The glyph's optical centre sits above its box's centre —
                // the crystal hangs below the chevron — so baseline-aligning
                // the BOX would ride high against the text.
                .alignmentGuide(.firstTextBaseline) { $0.height * 0.62 }
                headlineText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headlineText: some View {
        // `headline`, not `title`: the rail still labels this step "Welcome",
        // but the stage says what Ainkrad actually is. See `SetupStep.headline`.
        Text(coordinator.step.headline)
            .font(AinkradFont.display(SetupHeader.headlineSize, weight: .semibold))
            .foregroundStyle(tokens.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                alignment: coordinator.step.usesHeroMark ? .center : .leading
            )
            .transition(
                SetupStageMotion.layerTransition(
                    .heading, reduceMotion: reduceMotion, isForward: isForward)
            )
            .id(coordinator.step)
    }

}
