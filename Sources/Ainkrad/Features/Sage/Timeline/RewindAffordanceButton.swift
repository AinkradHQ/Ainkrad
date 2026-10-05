import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure view-model: maps checkpoints to menu rows so the mapping is testable
/// without SwiftUI. `canRestoreCode` is false only for a checkpoint that captured
/// nothing restorable (no file snapshot AND no git stash). Checkpoints already
/// come back newest-first from `CheckpointCoordinator.checkpoints()`, so this
/// preserves that order rather than re-sorting.
enum RewindMenuModel {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let title: String
        let canRestoreCode: Bool
    }

    static func rows(from checkpoints: [Checkpoint]) -> [Row] {
        checkpoints.map { cp in
            Row(
                id: cp.id, title: cp.label,
                canRestoreCode: !cp.fileSnapshots.isEmpty || cp.gitStashSHA != nil)
        }
    }
}

/// Hover-revealed rewind control shown on a user prompt bubble. Cardinal HUD:
/// chamfered panel, no native `Menu`/`.sheet`/`Picker` — a custom list of rows,
/// each offering code / chat / both restore. `onRestore` bridges to
/// `AgentSession.restoreCheckpoint(_:mode:)` at the call site.
///
/// Not yet wired into `SageRootView`'s user bubble: `AgentSession` only
/// exposes a private `checkpointer`, with no public `checkpoints()` accessor to
/// feed this view's `rows`. Wiring would require widening `AgentSession`'s
/// public surface, which is out of this task's scope — left standalone-but-
/// compiling per the task brief.
struct RewindAffordanceButton: View {
    let rows: [RewindMenuModel.Row]
    let tokens: DesignTokens
    let isVisible: Bool
    let onRestore: (UUID, CheckpointCoordinator.RestoreMode) -> Void
    @State private var isOpen = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : AinkradMotion.present) { isOpen.toggle() }
        } label: {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
        .buttonStyle(.plain)
        .opacity(isVisible || isOpen ? 1 : 0)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isVisible)
        .overlay(alignment: .topTrailing) {
            if isOpen { popover }
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.title).font(AinkradFont.display(11)).lineLimit(1)
                    Spacer(minLength: 8)
                    rewindChip("code", .code, enabled: row.canRestoreCode, id: row.id)
                    rewindChip("chat", .conversation, enabled: true, id: row.id)
                    rewindChip("both", .both, enabled: row.canRestoreCode, id: row.id)
                }
            }
        }
        .padding(10)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.background.opacity(0.95)))
        .overlay(ChamferShape(cut: AinkradRadius.sm).stroke(tokens.accentPrimary.opacity(0.3), lineWidth: 1))
        .frame(width: 320)
    }

    private func rewindChip(_ label: String, _ mode: CheckpointCoordinator.RestoreMode, enabled: Bool, id: UUID)
        -> some View
    {
        Button {
            onRestore(id, mode)
            isOpen = false
        } label: {
            Text(label).font(AinkradFont.mono(10))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(ChamferShape(cut: 3).fill(tokens.accentSecondary.opacity(enabled ? 0.18 : 0.05)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
