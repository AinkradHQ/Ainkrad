// design-lint: allow-file frame-literal,radius-literal,opacity-literal,font-size,padding-literal,spacing-literal,motion-literal island composition metrics, scaled by the view size
import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The Liquid Glass home island (`host.language.island: glass`): no painting —
/// separate live layers of glass. Two soft accent lights sit at the back so the
/// glass has something to bend; the brand slab and three glass islets float at
/// their own depths in one `GlassEffectContainer`, so when the drift brings two
/// close they merge like liquid. The chevron and wordmark ride the brand slab.
///
/// Each layer moves by its own depth: the pointer tilts the stack (parallax)
/// and an idle drift breathes it. Motion runs on `BudgetedTimelineView`
/// (frozen when the budget says so), stops when `isVisible` is false, and
/// settles to the still pose under Reduce Motion. Below macOS 26 the slabs
/// fall back to the system material.
struct GlassIslandView: View {
    var isVisible: Bool = true

    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    /// Pointer position in the view, -1...1 on each axis; zero at rest.
    @State private var pointer: CGPoint = .zero

    private var animates: Bool { isVisible && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if animates {
                    BudgetedTimelineView { date in
                        stack(in: size, time: date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    stack(in: size, time: 0)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard animates else { return }
                switch phase {
                case .active(let location):
                    pointer = CGPoint(
                        x: max(-1, min(1, location.x / max(size.width, 1) * 2 - 1)),
                        y: max(-1, min(1, location.y / max(size.height, 1) * 2 - 1)))
                case .ended:
                    pointer = .zero
                }
            }
            .animation(.smooth(duration: 0.6), value: pointer)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ainkrad")
    }

    /// The whole composition at `time`. Depth 0 is the back, 1 the front.
    private func stack(in size: CGSize, time: TimeInterval) -> some View {
        let unit = min(size.width / 860, size.height / 574)
        return ZStack {
            light(color: skin.color(skin.palette.accentPrimary), diameter: 360 * unit)
                .offset(layerOffset(depth: 0, unit: unit, time: time, phase: 0) + CGSize(width: -120 * unit, height: 40 * unit))
            light(color: skin.color(skin.palette.accentSecondary), diameter: 280 * unit)
                .offset(layerOffset(depth: 0.1, unit: unit, time: time, phase: 2) + CGSize(width: 150 * unit, height: -30 * unit))

            slabs(unit: unit, time: time)
        }
        .frame(width: size.width, height: size.height)
    }

    /// A soft coloured light behind the glass.
    private func light(color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.55))
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.28)
    }

    /// The glass layers: the brand slab in front, three islets around it at
    /// their own depths. They sit apart; only when the drift brings two
    /// close does the container merge them, like liquid.
    private struct Islet {
        let width: CGFloat, height: CGFloat, radius: CGFloat
        let x: CGFloat, y: CGFloat, depth: CGFloat, phase: Double
    }

    private static let islets = [
        Islet(width: 230, height: 78, radius: 30, x: -260, y: 150, depth: 0.45, phase: 1),
        Islet(width: 170, height: 62, radius: 26, x: 250, y: 128, depth: 0.6, phase: 3),
        Islet(width: 96, height: 44, radius: 20, x: 240, y: -170, depth: 0.3, phase: 4),
    ]

    @ViewBuilder
    private func slabs(unit: CGFloat, time: TimeInterval) -> some View {
        let top = RoundedRectangle(cornerRadius: 36 * unit, style: .continuous)
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 14 * unit) {
                ZStack {
                    ForEach(Array(Self.islets.enumerated()), id: \.offset) { _, islet in
                        Color.clear
                            .frame(width: islet.width * unit, height: islet.height * unit)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: islet.radius * unit, style: .continuous))
                            .offset(
                                layerOffset(depth: islet.depth, unit: unit, time: time, phase: islet.phase)
                                    + CGSize(width: islet.x * unit, height: islet.y * unit))
                    }
                    brandSlab(unit: unit)
                        .glassEffect(.regular, in: top)
                        .offset(layerOffset(depth: 1, unit: unit, time: time, phase: 5) + CGSize(width: 0, height: -20 * unit))
                }
            }
        } else {
            ZStack {
                ForEach(Array(Self.islets.enumerated()), id: \.offset) { _, islet in
                    RoundedRectangle(cornerRadius: islet.radius * unit, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: islet.width * unit, height: islet.height * unit)
                        .offset(x: islet.x * unit, y: islet.y * unit)
                }
                brandSlab(unit: unit).background(.ultraThinMaterial, in: top).offset(y: -20 * unit)
            }
        }
    }

    /// The front slab's content: the chevron over the wordmark.
    private func brandSlab(unit: CGFloat) -> some View {
        VStack(spacing: 14 * unit) {
            AinkradBrandChevron()
                .fill(
                    LinearGradient(
                        colors: [.white, skin.color(skin.palette.accentSecondary)],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 64 * unit, height: 54 * unit)
            Text("Ainkrad")
                .font(.system(size: 40 * unit, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
            Text("Build · Focus · Elevate")
                .font(.system(size: 13 * unit, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 56 * unit)
        .padding(.vertical, 36 * unit)
    }

    /// How far a layer at `depth` sits from its rest pose: the pointer tilt
    /// (front layers move most) plus a slow drift, out of step per layer.
    private func layerOffset(depth: CGFloat, unit: CGFloat, time: TimeInterval, phase: Double) -> CGSize {
        let tilt = 26 * unit * (0.2 + depth)
        let drift = animates ? 6 * unit * (0.4 + depth) : 0
        return CGSize(
            width: pointer.x * tilt + CGFloat(cos(time * 0.35 + phase)) * drift,
            height: pointer.y * tilt * 0.6 + CGFloat(sin(time * 0.45 + phase)) * drift)
    }
}

extension CGSize {
    fileprivate static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
