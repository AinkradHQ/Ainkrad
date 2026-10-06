import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The rail's leading gutter: a full-height tinted spine with a status node
/// marker at its top. Shared by committed steps, the live tail, and the pending
/// approval node so every rail node is identical by construction (not by
/// hand-copied markup).
struct TimelineRailGutter: View {
    @Environment(\.ainkradSkin) private var skin
    let status: StepStatus
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var statusColors
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(theme.accentPrimary.opacity(skin.opacity.o25))
                .frame(width: skin.size.s1)
                .frame(maxHeight: .infinity)
            TimelineNodeMarker(
                status: status, tint: theme.accentPrimary,
                errorColor: statusColors.danger, reduceMotion: reduceMotion
            )
            .padding(.top, skin.size.s3)
        }
        .frame(width: skin.size.s10)
    }
}

/// The "Thinking" disclosure row shared by committed thinking steps and the live
/// tail. Expansion state is owned by the caller (a committed turn keys it by
/// step id; the live tail holds a single bool), passed in as `isExpanded` +
/// `onToggle` so the row itself stays stateless.
struct TimelineThinkingRow: View {
    @Environment(\.ainkradSkin) private var skin
    let text: String
    let isExpanded: Bool
    @Environment(\.ainkradTheme) private var theme
    let onToggle: () -> Void

    var body: some View {
        // The kit disclosure animates its own expansion; the caller still owns
        // the state, so the binding only reads it and reports a toggle.
        AinkradDisclosureGroup(
            title: "Thinking", isExpanded: Binding(get: { isExpanded }, set: { _ in onToggle() })
        ) {
            Text(text)
                .font(AinkradFont.mono(11))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
                .textSelection(.enabled)
        }
    }
}
