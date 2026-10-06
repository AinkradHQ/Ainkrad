import Foundation
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("Setup stage")
@MainActor
struct SetupStageTests {
    // The rail shows the steps actually owed, so there is no denominator that
    // can contradict itself when the step list changes at the vault swap.
    @Test func theRailReflectsOwedStepsNotAFixedCount() {
        let store = InMemoryPersistenceStore()
        let provisional = SetupCoordinator(persistence: store, isProvisionalHome: true)
        let adopted = SetupCoordinator(persistence: store, isProvisionalHome: false)

        #expect(SetupRailModel(coordinator: provisional).items.count == provisional.steps.count)
        #expect(SetupRailModel(coordinator: adopted).items.count == adopted.steps.count)

        // The rail drops `.home` only once setup has COMPLETED in the vault.
        // Mid-wizard the folder stays changeable, so the rail still shows it —
        // a rail that hid a step the user can still reach would misreport where
        // they are.
        let settledStore = InMemoryPersistenceStore()
        settledStore.save(
            SetupDocument(
                completedAt: Date(),
                setupVersion: SetupCoordinator.currentSetupVersion,
                deferredSteps: [SetupStep.providers.rawValue]))
        let settled = SetupCoordinator(persistence: settledStore, isProvisionalHome: false)
        #expect(!SetupRailModel(coordinator: settled).items.contains { $0.step == .home })
    }

    @Test func theRailMarksExactlyOneStepCurrent() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.advance()
        let items = SetupRailModel(coordinator: c).items
        #expect(items.filter(\.isCurrent).count == 1)
        #expect(items.first(where: \.isCurrent)?.step == c.step)
    }

    // Reduce-motion is set two steps into this wizard. The remaining steps must
    // honour it immediately — it is the most visible proof the setting works.
    @Test func reduceMotionRemovesTheStageTransition() {
        #expect(SetupStageMotion.transition(reduceMotion: true) == .none)
        #expect(SetupStageMotion.transition(reduceMotion: false) != .none)
    }

    // Steps behind the current one read as done; steps ahead do not. This is
    // what makes the rail spatial — the lit segment IS the position.
    @Test func theRailMarksOnlyPassedStepsComplete() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.advance()
        c.advance()
        let items = SetupRailModel(coordinator: c).items
        let current = items.firstIndex(where: { $0.isCurrent }) ?? 0
        let behindAllComplete = items[..<current].allSatisfy { $0.isComplete }
        let aheadNoneComplete = !items[current...].contains { $0.isComplete }
        #expect(behindAllComplete)
        #expect(aheadNoneComplete)
    }

    // `transition` is only ONE of the three reduce-motion seams. This is the
    // second: `animation` returning nil is what makes the container's and the
    // rail's `.animation(_, value:)` no-ops. Without this test its guard could
    // be deleted and the rail would keep animating with the suite still green.
    @Test func reduceMotionRemovesTheStageAnimation() {
        for layer in SetupStageMotion.Layer.allCases {
            #expect(SetupStageMotion.animation(reduceMotion: true, layer: layer) == nil)
            #expect(SetupStageMotion.animation(reduceMotion: false, layer: layer) != nil)
        }
    }

    // The stage's feel: one spring, and each layer a fixed beat behind the one
    // above it. Pinned before the spring moves onto a skin token, so the token
    // has to resolve to exactly today's response, damping and stagger.
    @Test func theStageSpringAndStaggerKeepTheirFeel() {
        for layer in SetupStageMotion.Layer.allCases {
            #expect(
                SetupStageMotion.animation(reduceMotion: false, layer: layer)
                    == Animation.spring(response: 0.42, dampingFraction: 0.82)
                    .delay(Double(layer.rawValue) * 0.055))
        }
    }

    // The third seam: the per-layer geometry, which is what `layerTransition`
    // falls back to `.identity` on.
    @Test func reduceMotionRemovesEveryLayerGeometry() {
        for layer in SetupStageMotion.Layer.allCases {
            #expect(
                SetupStageMotion.layerGeometry(
                    layer, reduceMotion: true,
                    isForward: true) == nil)
            #expect(
                SetupStageMotion.layerGeometry(
                    layer, reduceMotion: true,
                    isForward: false) == nil)
            #expect(
                SetupStageMotion.layerGeometry(
                    layer, reduceMotion: false,
                    isForward: true) != nil)
        }
    }

    // Each layer must travel a different distance, or they read as one plane
    // sliding rather than separated live layers.
    @Test func layersTravelIndependently() {
        let distances = SetupStageMotion.Layer.allCases.compactMap {
            SetupStageMotion.layerGeometry($0, reduceMotion: false, isForward: true)
        }
        #expect(distances.count == SetupStageMotion.Layer.allCases.count)
        #expect(Set(distances.map(\.travel)).count == distances.count)
        #expect(Set(distances.map(\.delay)).count == distances.count)
    }

    // Direction is a pure function of the two step indices so the stage can
    // compute it DURING body evaluation. Deriving it afterwards (in onChange)
    // left every transition one step behind, and the first Back animated as a
    // forward.
    @Test func directionComesFromTheStepIndicesAlone() {
        #expect(SetupStageMotion.isForward(from: 2, to: 3))
        #expect(!SetupStageMotion.isForward(from: 3, to: 2))
        // No movement is not "backwards": the first render compares a step
        // against itself and must not animate in reverse.
        #expect(SetupStageMotion.isForward(from: 0, to: 0))
    }

    // MARK: - Composition
    //
    // The stage is full-bleed, but the CONTENT must not be. Hand-testing on a
    // 1728x1084 window found the headline in the top-left, the paragraph below
    // it, and the only button roughly 1000pt down and 700pt across in the
    // bottom-right corner — far enough apart that the user reported the wizard
    // as having no buttons at all, and could not reach step 2.
    //
    // The rule: the step is ONE group, bounded and centred. Empty space goes
    // around it, never through it.

    @Test func theContentColumnIsBoundedOnAWideWindow() {
        let wide = SetupStageLayout.group(fitting: CGSize(width: 1728, height: 1084))
        #expect(wide.width <= SetupStageLayout.maximumColumnWidth)
        #expect(wide.height <= SetupStageLayout.maximumGroupHeight)
    }

    // The failure mode that made this bug invisible in review: at a normal
    // window size the layout looked fine, so the bound has to be proven to bite
    // only when it should.
    @Test func aSmallWindowIsNotPaddedIntoUselessness() {
        let small = CGSize(width: 720, height: 560)
        let group = SetupStageLayout.group(fitting: small)
        #expect(group.width < small.width)
        #expect(group.height < small.height)
        // …but it still uses most of what it was given, rather than shrinking to
        // the same island a 1728pt window gets.
        #expect(group.width > small.width * 0.7)
        #expect(group.height > small.height * 0.6)
    }

    // Monotonic: a bigger window never yields a smaller group. Without this a
    // clamp expressed as a subtraction could invert at some size and nobody
    // would notice until a user with that display reported it.
    @Test func theGroupNeverShrinksAsTheWindowGrows() {
        var previous = CGSize.zero
        for width in stride(from: CGFloat(480), through: 3000, by: 120) {
            let group = SetupStageLayout.group(fitting: CGSize(width: width, height: width * 0.62))
            #expect(group.width >= previous.width)
            #expect(group.height >= previous.height)
            previous = group
        }
    }

    // The complaint that raised the caps: the group sat still while the window
    // grew around it, so a large window showed a small card marooned in space.
    // It must visibly track the window across the sizes people actually use.
    @Test func theGroupGrowsAcrossRealisticWindowSizes() {
        let small = SetupStageLayout.group(fitting: CGSize(width: 900, height: 640))
        let medium = SetupStageLayout.group(fitting: CGSize(width: 1280, height: 820))
        let large = SetupStageLayout.group(fitting: CGSize(width: 1728, height: 1084))

        #expect(medium.width > small.width + 100, "a 380pt wider window must show it")
        #expect(large.width > medium.width + 100)
        #expect(medium.height > small.height)
        #expect(large.height > medium.height)
    }

    // …while still holding margin back. A group that simply filled the window
    // is the bug this whole type exists to prevent.
    @Test func theGroupNeverFillsTheWindow() {
        for size in [
            CGSize(width: 900, height: 640),
            CGSize(width: 1280, height: 820),
            CGSize(width: 1728, height: 1084),
            CGSize(width: 2560, height: 1440),
        ] {
            let group = SetupStageLayout.group(fitting: size)
            #expect(group.width < size.width)
            #expect(group.height < size.height)
        }
        // And the margin WIDENS as the window does, rather than staying a fixed
        // sliver — which is what makes a big window read as composed.
        let narrow = CGSize(width: 1000, height: 700)
        let wide = CGSize(width: 2000, height: 1200)
        let narrowMargin = narrow.width - SetupStageLayout.group(fitting: narrow).width
        let wideMargin = wide.width - SetupStageLayout.group(fitting: wide).width
        #expect(wideMargin > narrowMargin)
    }

    // MARK: - Measures within the group
    //
    // Widening the group introduced a hazard it did not have at 680: steps that
    // filled it would run their text to 1100pt. So a step has two measures.

    @Test func proseIsHeldToAReadableMeasureHoweverWideTheWindow() {
        for width in stride(from: CGFloat(600), through: 3000, by: 100) {
            let group = SetupStageLayout.group(fitting: CGSize(width: width, height: 900))
            let reading = SetupStageLayout.readingWidth(inGroupOf: group.width)
            // ~75 characters at the wizard's body size. Past this the eye loses
            // the line it is returning to.
            #expect(reading <= 680)
            #expect(reading <= group.width)
        }
    }

    // Panels fill the group rather than taking a measure of their own, so the
    // only thing that must never exceed it is prose.
    @Test func proseNeverEscapesItsGroup() {
        for width in stride(from: CGFloat(400), through: 3000, by: 100) {
            let group = SetupStageLayout.group(fitting: CGSize(width: width, height: 900))
            #expect(SetupStageLayout.readingWidth(inGroupOf: group.width) <= group.width)
        }
    }

    // Both measures have to actually respond, or "responsive" is only true of
    // the group and every step still looks fixed inside it.
    @Test func theReadingMeasureGrowsWithTheWindow() {
        let small = SetupStageLayout.group(fitting: CGSize(width: 900, height: 640)).width
        let large = SetupStageLayout.group(fitting: CGSize(width: 1728, height: 1084)).width

        #expect(
            SetupStageLayout.readingWidth(inGroupOf: large)
                > SetupStageLayout.readingWidth(inGroupOf: small))
    }

    // On a narrow window the measures must not exceed what there is — that is
    // how content clips instead of merely being cramped.
    @Test func theMeasuresSurviveANarrowWindow() {
        let group = SetupStageLayout.group(fitting: CGSize(width: 520, height: 420))
        #expect(SetupStageLayout.readingWidth(inGroupOf: group.width) <= group.width)
        #expect(SetupStageLayout.readingWidth(inGroupOf: group.width) > 0)
    }

    // A window smaller than the group's own bounds must not produce a negative
    // or zero size — that is how content vanishes entirely rather than merely
    // being cramped.
    @Test func anAbsurdlySmallWindowStillProducesAUsableGroup() {
        for size in [CGSize(width: 200, height: 150), CGSize(width: 1, height: 1), .zero] {
            let group = SetupStageLayout.group(fitting: size)
            #expect(group.width > 0)
            #expect(group.height > 0)
        }
    }

    // Exactly one step shows the mark as its subject. The stage renders ONE
    // mark and picks its arrangement from this, so a second claimant would mean
    // two hero marks competing for the same matchedGeometry identity.
    @Test func onlyWelcomeShowsTheHeroMark() {
        let hero = SetupStep.allCases.filter(\.usesHeroMark)
        #expect(hero == [.welcome])
    }

    // The inline mark is sized to sit ON the headline's line. If these drift
    // apart the mark reads as an icon parked beside some text rather than as
    // part of the heading.
    @Test func theInlineMarkMatchesTheHeadlineHeight() {
        #expect(SetupHeader.inlineMarkHeight == SetupHeader.headlineSize)
    }

    // The hero and the inline mark must be the SAME element to animate between
    // arrangements, which means one shared identity. A typo in either literal
    // would not fail the build — the mark would just stop animating — so the
    // constant is the guard and this pins that it stays one.
    @Test func theMarkTravelsUnderOneIdentity() {
        #expect(!SetupHeader.markID.isEmpty)
    }

    // A step that draws its own headline must still HAVE one to draw — the
    // property and the copy are set in two different places and nothing else
    // connects them.
    @Test func everyStepStillHasAHeadline() {
        for step in SetupStep.allCases {
            #expect(!step.headline.isEmpty)
        }
    }

    // Forward and back must be directionally distinct, so the policy has to
    // carry a direction and collapse it only under reduce-motion.
    @Test func directionSurvivesUntilReduceMotionCollapsesIt() {
        #expect(
            SetupStageMotion.transition(reduceMotion: false, isForward: true)
                != SetupStageMotion.transition(reduceMotion: false, isForward: false))
        #expect(
            SetupStageMotion.transition(reduceMotion: true, isForward: true)
                == SetupStageMotion.transition(reduceMotion: true, isForward: false))
    }
}
