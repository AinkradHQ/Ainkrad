import AinkradAppKit
import SwiftUI

// MARK: - Motion policy

/// The stage's motion policy, kept separate from the views so the one rule that
/// actually matters — reduce-motion collapses everything — is unit-testable.
///
/// The wizard SETS `uiReduceMotion` two steps in. A user who turns it on at
/// Motion & Sound must see the remaining steps stop moving immediately; that is
/// the most visible possible proof the setting works, and animating anyway is
/// worse than never having animated at all.
enum SetupStageMotion {
    /// What the stage does when the step changes. `.none` is the whole point of
    /// this type existing: it is the seam reduce-motion collapses to.
    enum Transition: Equatable {
        case none
        /// Layers enter offset in the direction of travel and stagger in.
        case layered(isForward: Bool)
    }

    /// The layers, outermost first. Each one animates as its own element — the
    /// design language's "separated live layers, not one whole image moving".
    enum Layer: Int, CaseIterable {
        case rail = 0, heading, content
    }

    /// How far and how late a layer moves. Pure data so the geometry — and the
    /// reduce-motion guard in front of it — can be asserted without SwiftUI.
    struct LayerGeometry: Equatable {
        /// Signed horizontal travel of the ENTERING layer, in points. Negative
        /// when going back, which is what makes the two directions distinct.
        let travel: CGFloat
        let lift: CGFloat
        let delay: Double
    }

    /// Direction of travel between two steps. A free function of the two step
    /// indices, so it can be computed during body evaluation from the step being
    /// rendered rather than recovered afterwards.
    static func isForward(from previousIndex: Int, to nextIndex: Int) -> Bool {
        nextIndex >= previousIndex
    }

    static func transition(reduceMotion: Bool, isForward: Bool = true) -> Transition {
        reduceMotion ? .none : .layered(isForward: isForward)
    }

    /// `nil` under reduce-motion — the seam that makes `layerTransition` fall
    /// back to `.identity`.
    static func layerGeometry(
        _ layer: Layer,
        reduceMotion: Bool,
        isForward: Bool
    ) -> LayerGeometry? {
        guard case .layered = transition(reduceMotion: reduceMotion, isForward: isForward) else {
            return nil
        }
        // A `switch`, not an indexed array: a fourth Layer case must fail to
        // compile rather than silently inherit the third one's geometry.
        let distance: CGFloat
        let lift: CGFloat
        switch layer {
        case .rail:
            distance = 26
            lift = 0
        case .heading:
            distance = 34
            lift = 6
        case .content:
            distance = 46
            lift = 10
        }
        return LayerGeometry(
            travel: isForward ? distance : -distance,
            lift: lift,
            delay: Double(layer.rawValue) * 0.055)
    }

    /// `nil` under reduce-motion, which makes every `withAnimation` /
    /// `.animation` call site a no-op without a branch at each one.
    ///
    /// The spring is the skin's `sp42_82`, read from `AinkradSkin.standard`
    /// because this policy is static and has no environment to read a skin
    /// from (the same arrangement as `OverlayChrome`).
    static func animation(reduceMotion: Bool, layer: Layer = .rail) -> Animation? {
        guard !reduceMotion, let spring = AinkradSkin.standard.motion.springs["sp42_82"] else { return nil }
        return AinkradSkin.standard.animation(spring)
            .delay(Double(layer.rawValue) * 0.055)
    }

    /// The per-layer entry/exit. Forward and back are directionally distinct
    /// (content arrives from the side it is travelling from), and each layer
    /// carries a slightly different distance and delay so they do not read as
    /// one plane sliding.
    static func layerTransition(
        _ layer: Layer,
        reduceMotion: Bool,
        isForward: Bool
    ) -> AnyTransition {
        guard
            let geometry = layerGeometry(
                layer,
                reduceMotion: reduceMotion,
                isForward: isForward)
        else {
            return .identity
        }

        let insertion =
            AnyTransition
            .offset(x: geometry.travel, y: geometry.lift)
            .combined(with: .opacity)
        let removal =
            AnyTransition
            .offset(x: -geometry.travel * 0.6, y: 0)
            .combined(with: .opacity)

        return
            AnyTransition
            .asymmetric(insertion: insertion, removal: removal)
            .animation(animation(reduceMotion: reduceMotion, layer: layer))
    }
}
