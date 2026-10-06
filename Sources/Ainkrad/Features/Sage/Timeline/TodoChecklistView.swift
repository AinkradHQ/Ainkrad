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
    let items: [TodoItem]
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 11)).foregroundStyle(theme.accentSecondary)
                Text("Tasks").font(AinkradFont.display(11, weight: .semibold)).kerning(1)
                    .foregroundStyle(theme.accentSecondary.opacity(0.85))
                Spacer(minLength: 8)
                Text(TodoStepPresentation.summary(items))
                    .font(AinkradFont.mono(10)).foregroundStyle(theme.foreground.opacity(0.5))
            }
            ForEach(items) { item in row(item) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(theme.background.opacity(0.45)))
        .overlay {
            ChamferShape(cut: AinkradRadius.sm).stroke(theme.accentSecondary.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func row(_ item: TodoItem) -> some View {
        let done = TodoStepPresentation.isDone(item.status)
        let icon = Image(systemName: TodoStepPresentation.glyph(item.status))
            .font(.system(size: 11))
            .foregroundStyle(
                done
                    ? statusColors.success
                    : (item.status == .inProgress ? theme.accentSecondary : theme.foreground.opacity(0.4)))
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if item.status == .inProgress && !reduceMotion {
                BudgetedTimelineView { date in
                    let wave = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate / AinkradMotion.durationBase)
                    icon.opacity(0.5 + 0.5 * wave)
                }
            } else {
                icon
            }
            Text(item.content)
                .font(AinkradFont.display(12, weight: done ? .regular : .medium))
                .strikethrough(done, color: theme.foreground.opacity(0.4))
                .foregroundStyle(theme.foreground.opacity(done ? 0.45 : 0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
