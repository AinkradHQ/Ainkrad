import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure diff→row helpers (no SwiftUI) so the pairing logic is unit-tested.
enum DiffReviewPresentation {
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

/// Rich approval-card diff: a kit latch toggling unified/side-by-side (NO
/// native Picker) and a per-hunk Accept/Reject latch. Rejection is owned by the caller
/// (session state) via a binding so the docked approve button reads the same set.
struct DiffReviewView: View {
    @Environment(\.ainkradSkin) private var skin
    let fileDiff: FileDiff
    @Binding var rejectedHunkIDs: Set<Int>
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var statusColors
    @State private var sideBySide = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            header
            ForEach(fileDiff.hunks) { hunk in hunkBlock(hunk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: skin.spacing.sm) {
            Text(fileDiff.path).font(AinkradFont.mono(10)).foregroundStyle(theme.foreground.opacity(skin.opacity.o55))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            AinkradToggleButton(
                isOn: $sideBySide.animation(reduceMotion ? nil : AinkradMotion.present), title: "Split")
        }
    }

    @ViewBuilder
    private func hunkBlock(_ hunk: DiffHunk) -> some View {
        let rejected = rejectedHunkIDs.contains(hunk.id)
        VStack(alignment: .leading, spacing: skin.size.s3) {
            HStack(spacing: skin.size.s6) {
                Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount)")
                    .font(AinkradFont.mono(9)).foregroundStyle(theme.foreground.opacity(skin.opacity.o40))
                Spacer(minLength: 6)
                AinkradToggleButton(isOn: acceptedBinding(hunk.id), title: rejected ? "Rejected" : "Accepted")
            }
            if sideBySide { splitRows(hunk) } else { unifiedRows(hunk) }
        }
        .opacity(rejected ? skin.opacity.o50 : 1)
        .padding(.horizontal, skin.spacing.sm).padding(.vertical, skin.size.s6)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(theme.background.opacity(skin.opacity.o40)))
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
                HStack(alignment: .top, spacing: skin.spacing.sm) {
                    Text(pair.left?.text ?? "").font(AinkradFont.mono(11))
                        .foregroundStyle(pair.left.map(color) ?? theme.foreground.opacity(skin.opacity.o20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(pair.right?.text ?? "").font(AinkradFont.mono(11))
                        .foregroundStyle(pair.right.map(color) ?? theme.foreground.opacity(skin.opacity.o20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A hunk is accepted unless the caller's set rejects it; the latch is lit
    /// while accepted.
    private func acceptedBinding(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { !rejectedHunkIDs.contains(id) },
            set: { accepted in
                if accepted { rejectedHunkIDs.remove(id) } else { rejectedHunkIDs.insert(id) }
            })
    }

    private func color(_ line: DiffLine) -> Color {
        switch line.kind {
        case .insertion: return statusColors.success
        case .deletion: return statusColors.danger
        case .context: return theme.foreground.opacity(skin.opacity.o60)
        }
    }
}
