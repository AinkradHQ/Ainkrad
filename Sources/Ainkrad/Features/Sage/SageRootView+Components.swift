import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Copy-to-pasteboard for a whole assistant turn, revealed on hover.
struct SageTurnCopyButton: View {
    let text: String
    /// Driven by the enclosing turn's hover region, not this button's own frame —
    /// the button sits at `opacity: 0` until the whole turn is hovered, so tying
    /// visibility to a local `.onHover` on the icon-sized frame made it undiscoverable.
    var isVisible: Bool
    @State private var copied = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        AinkradIconButton(systemName: copied ? "checkmark" : "doc.on.doc", size: 20, tooltip: "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        }
        .opacity(isVisible ? 0.8 : 0)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isVisible)
        // The checkmark reverts after a beat; a structured task, so it is
        // cancelled with the button rather than outliving it.
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

/// Blinking caret shown at the tail of streaming output; steady under reduce-motion.
struct StreamingCursor: View {
    let tokens: DesignTokens
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            caret(opacity: 1)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                caret(opacity: on ? 1 : 0.15)
            }
        }
    }

    private func caret(opacity: Double) -> some View {
        Text("▍").font(AinkradFont.display(13)).foregroundStyle(tokens.accentSecondary.opacity(opacity))
    }
}

/// Breathing "working" affordance shown before the first streamed token and while a
/// tool call is spinning up before its card commits. Steady under Reduce Motion
/// (mirrors `StreamingCursor`).
struct WorkingIndicator: View {
    let tokens: DesignTokens
    var label: String = "Thinking"
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            dots
            Text("\(label)…")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.45))
        }
    }

    // TimelineView-driven so the pulse actually runs — a one-shot `@State`
    // toggle with `.repeatForever(.animation(value:))` frequently never starts.
    // Same idiom as `StreamingCursor` above.
    @ViewBuilder private var dots: some View {
        if reduceMotion {
            HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in dot(0.7) } }
        } else {
            BudgetedTimelineView { date in
                let t = date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        // ~1.6s breathe (2π·durationBase), 60° per-dot stagger.
                        let phase = t / AinkradMotion.durationBase + Double(i) * .pi / 3
                        dot(0.3 + 0.6 * (0.5 + 0.5 * sin(phase)))
                    }
                }
            }
        }
    }

    private func dot(_ opacity: Double) -> some View {
        Circle().fill(tokens.accentSecondary.opacity(opacity)).frame(width: 4, height: 4)
    }
}
