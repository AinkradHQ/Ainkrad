import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure diff→row helpers (no SwiftUI) so pairing/tint logic is unit-tested.
enum DiffReviewPresentation {
    static func isTinted(_ line: DiffLine) -> Bool { line.kind != .context }

    /// Pair deletions (left) with insertions (right) for side-by-side rendering.
    /// Context lines mirror on both sides; unmatched del/ins get an empty slot.
    static func sideBySideRows(_ hunk: DiffHunk) -> [(left: DiffLine?, right: DiffLine?)] {
        var rows: [(DiffLine?, DiffLine?)] = []
        var pendingDel: [DiffLine] = []
        var pendingIns: [DiffLine] = []
        func flush() {
            let n = max(pendingDel.count, pendingIns.count)
            for k in 0..<n {
                rows.append(
                    (
                        k < pendingDel.count ? pendingDel[k] : nil,
                        k < pendingIns.count ? pendingIns[k] : nil
                    ))
            }
            pendingDel.removeAll()
            pendingIns.removeAll()
        }
        for line in hunk.lines {
            switch line.kind {
            case .context:
                flush()
                rows.append((line, line))
            case .deletion: pendingDel.append(line)
            case .insertion: pendingIns.append(line)
            }
        }
        flush()
        return rows
    }
}

/// Rich approval-card diff: a custom unified/side-by-side toggle (NO native
/// Picker) and a per-hunk Accept/Reject chip. Rejection is owned by the caller
/// (session state) via a binding so the docked approve button reads the same set.
struct DiffReviewView: View {
    let fileDiff: FileDiff
    @Binding var rejectedHunkIDs: Set<Int>
    let tokens: DesignTokens
    @State private var sideBySide = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(fileDiff.hunks) { hunk in hunkBlock(hunk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(fileDiff.path).font(AinkradFont.mono(10)).foregroundStyle(tokens.foreground.opacity(0.55))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            ModeChip(title: sideBySide ? "Split" : "Unified", tokens: tokens) {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) { sideBySide.toggle() }
            }
        }
    }

    @ViewBuilder
    private func hunkBlock(_ hunk: DiffHunk) -> some View {
        let rejected = rejectedHunkIDs.contains(hunk.id)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount)")
                    .font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.4))
                Spacer(minLength: 6)
                ModeChip(
                    title: rejected ? "Rejected" : "Accepted",
                    tint: rejected ? tokens.danger : tokens.success, tokens: tokens
                ) {
                    if rejected { rejectedHunkIDs.remove(hunk.id) } else { rejectedHunkIDs.insert(hunk.id) }
                }
            }
            if sideBySide { splitRows(hunk) } else { unifiedRows(hunk) }
        }
        .opacity(rejected ? 0.5 : 1)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.background.opacity(0.4)))
    }

    @ViewBuilder private func unifiedRows(_ hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                let sign = line.kind == .insertion ? "+" : (line.kind == .deletion ? "-" : " ")
                Text(sign + line.text).font(AinkradFont.mono(11))
                    .foregroundStyle(color(line)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func splitRows(_ hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(DiffReviewPresentation.sideBySideRows(hunk).enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top, spacing: 8) {
                    Text(pair.left?.text ?? "").font(AinkradFont.mono(11))
                        .foregroundStyle(pair.left.map(color) ?? tokens.foreground.opacity(0.2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(pair.right?.text ?? "").font(AinkradFont.mono(11))
                        .foregroundStyle(pair.right.map(color) ?? tokens.foreground.opacity(0.2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func color(_ line: DiffLine) -> Color {
        switch line.kind {
        case .insertion: return tokens.success
        case .deletion: return tokens.danger
        case .context: return tokens.foreground.opacity(0.6)
        }
    }
}

/// A small chamfered text chip with a hover fill — the Cardinal HUD stand-in for
/// a toggle/segmented control (no native controls allowed).
private struct ModeChip: View {
    let title: String
    var tint: Color? = nil
    let tokens: DesignTokens
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    var body: some View {
        let c = tint ?? tokens.accentPrimary
        Button(action: action) {
            Text(title).font(AinkradFont.display(10, weight: .medium)).kerning(0.4)
                .foregroundStyle(c.opacity(hovering ? 1 : 0.85))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(ChamferShape(cut: AinkradRadius.sm).fill(c.opacity(hovering ? 0.18 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: hovering)
    }
}
