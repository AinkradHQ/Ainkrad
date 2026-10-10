import Foundation
import AinkradAppKit

/// Rebuilds file content from the original + a subset of accepted hunks. A
/// rejected hunk contributes its ORIGINAL lines; an accepted hunk contributes
/// its NEW lines; everything outside any hunk is copied verbatim from the
/// original. Hunks are non-overlapping and sorted by `oldStart` (AinkradDiffEngine
/// guarantees this).
enum PartialEdit {
    static func reconstruct(_ diff: AinkradFileDiff, rejecting rejectedHunkIDs: Set<Int>) -> String {
        let originalLines = diff.original.isEmpty ? [] : diff.original.components(separatedBy: "\n")
        var out: [String] = []
        var cursor = 0  // 0-based index into originalLines
        for hunk in diff.hunks.sorted(by: { $0.oldStart < $1.oldStart }) {
            // `oldStart` is 1-based; a pure top insertion has oldStart == 0 or covers no old lines.
            let hunkOldStartIndex = max(0, hunk.oldStart - 1)
            if hunkOldStartIndex > cursor { out.append(contentsOf: originalLines[cursor..<hunkOldStartIndex]) }
            let accepted = !rejectedHunkIDs.contains(hunk.id)
            out.append(contentsOf: accepted ? hunk.newLines : hunk.oldLines)
            cursor = hunkOldStartIndex + hunk.oldCount
        }
        if cursor < originalLines.count { out.append(contentsOf: originalLines[cursor...]) }
        return out.joined(separator: "\n")
    }
}
