import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure status→glyph mapping for the checklist node (no SwiftUI), unit-tested
/// like `ToolPresentation`.
enum TodoStepPresentation {
    static func glyph(_ status: TodoItem.Status) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }
    static func isDone(_ status: TodoItem.Status) -> Bool { status == .completed }
    static func summary(_ items: [TodoItem]) -> String {
        "\(items.filter { $0.status == .completed }.count) / \(items.count)"
    }
}

/// The live task checklist rendered as a single timeline node. Chamfered panel,
/// no separators; the in-progress row breathes (gated on Reduce Motion), and
/// completed rows dim + strike. Updated in place as the agent revises the list
/// (the builder keeps only the latest `todo_write`).
struct TodoChecklistView: View {
    @Environment(\.ainkradSkin) private var skin
    let items: [TodoItem]
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            HStack(spacing: skin.size.s6) {
                Image(systemName: "checklist").font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false))).foregroundStyle(theme.accentSecondary)
                Text("Tasks").font(AinkradFont.display(11, weight: .semibold)).kerning(1)
                    .foregroundStyle(theme.accentSecondary.opacity(skin.opacity.o85))
                Spacer(minLength: 8)
                Text(TodoStepPresentation.summary(items))
                    .font(AinkradFont.mono(10)).foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
            }
            ForEach(items) { item in row(item) }
        }
        .padding(.horizontal, skin.size.s10).padding(.vertical, skin.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(skin.shape(cut: AinkradRadius.sm).fill(theme.background.opacity(skin.opacity.o45)))
        .overlay {
            skin.shape(cut: AinkradRadius.sm).stroke(theme.accentSecondary.opacity(skin.opacity.o22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func row(_ item: TodoItem) -> some View {
        let done = TodoStepPresentation.isDone(item.status)
        let icon = Image(systemName: TodoStepPresentation.glyph(item.status))
            .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
            .foregroundStyle(
                done
                    ? statusColors.success
                    : (item.status == .inProgress ? theme.accentSecondary : theme.foreground.opacity(skin.opacity.o40)))
        HStack(alignment: .firstTextBaseline, spacing: skin.size.s7) {
            if item.status == .inProgress && !reduceMotion {
                BudgetedTimelineView { date in
                    let wave = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate / AinkradMotion.durationBase)
                    icon.opacity(skin.opacity.o50 + skin.opacity.o50 * wave)
                }
            } else {
                icon
            }
            Text(item.content)
                .font(AinkradFont.display(12, weight: done ? .regular : .medium))
                .strikethrough(done, color: theme.foreground.opacity(skin.opacity.o40))
                .foregroundStyle(theme.foreground.opacity(done ? skin.opacity.o45 : skin.opacity.o85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
