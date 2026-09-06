import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Leading history-sidebar toggle with a hover highlight (motion is first-class in the HUD).
struct HoverSidebarToggle: View {
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foreground.opacity(isHovering ? 0.9 : 0.6))
                .padding(6)
                .background(Circle().fill(tokens.surfaceElevated.opacity(isHovering ? 0.75 : 0.5)))
        }
        .buttonStyle(.plain)
        .help("Toggle history")
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}

/// Retry control for the failed-turn error card. Hover-lit, chamfered — no native button chrome.
struct ErrorRetryButton: View {
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                Text("Retry").font(AinkradFont.display(11, weight: .medium))
            }
            .foregroundStyle(tokens.accentTertiary.opacity(isHovering ? 1 : 0.85))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentTertiary.opacity(isHovering ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        }
        .opacity(isVisible ? 0.8 : 0)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isVisible)
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
