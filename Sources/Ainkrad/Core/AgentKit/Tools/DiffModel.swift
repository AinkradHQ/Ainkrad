import Foundation

struct DiffLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case context, insertion, deletion }
    let kind: Kind
    let oldNumber: Int?  // 1-based line number in the original, nil for insertions
    let newNumber: Int?  // 1-based line number in the updated file, nil for deletions
    let text: String
}

struct DiffHunk: Equatable, Sendable, Identifiable {
    let id: Int  // stable index within the FileDiff (0-based)
    let oldStart: Int  // 1-based first original line the hunk covers (0 if pure insertion at top)
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]

    var oldLines: [String] { lines.filter { $0.kind != .insertion }.map(\.text) }
    var newLines: [String] { lines.filter { $0.kind != .deletion }.map(\.text) }
}

struct FileDiff: Equatable, Sendable {
    let path: String
    let original: String
    let hunks: [DiffHunk]
}

/// Line-level diff via a classic LCS table, grouped into hunks with `context`
/// unchanged lines of padding. Sufficient for edit-approval review — not a
/// minimal-edit myers diff, but stable and correct for reconstruction.
enum DiffEngine {
    static func compute(old: String, new: String, path: String, context: Int = 3) -> FileDiff {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")

        // LCS length table.
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if a.count > 0 && b.count > 0 {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        // Backtrack into a flat op list.
        enum Op { case ctx(String, Int, Int), ins(String, Int), del(String, Int) }
        var ops: [Op] = []
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                ops.append(.ctx(a[i], i + 1, j + 1))
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                ops.append(.del(a[i], i + 1))
                i += 1
            } else {
                ops.append(.ins(b[j], j + 1))
                j += 1
            }
        }
        while i < a.count {
            ops.append(.del(a[i], i + 1))
            i += 1
        }
        while j < b.count {
            ops.append(.ins(b[j], j + 1))
            j += 1
        }

        // Indices of changed ops, expanded by `context`, coalesced into ranges.
        let changed = ops.enumerated().filter { if case .ctx = $0.element { return false } else { return true } }.map(
            \.offset)
        guard !changed.isEmpty else { return FileDiff(path: path, original: old, hunks: []) }
        var ranges: [(Int, Int)] = []
        for idx in changed {
            let lo = max(0, idx - context)
            let hi = min(ops.count - 1, idx + context)
            if var last = ranges.last, lo <= last.1 + 1 {
                last.1 = max(last.1, hi)
                ranges[ranges.count - 1] = last
            } else {
                ranges.append((lo, hi))
            }
        }

        var hunks: [DiffHunk] = []
        for (hIndex, range) in ranges.enumerated() {
            var dlines: [DiffLine] = []
            var oStart = 0
            var nStart = 0
            var oCount = 0
            var nCount = 0
            for k in range.0...range.1 {
                switch ops[k] {
                case .ctx(let t, let on, let nn):
                    dlines.append(DiffLine(kind: .context, oldNumber: on, newNumber: nn, text: t))
                    if oStart == 0 { oStart = on }
                    if nStart == 0 { nStart = nn }
                    oCount += 1
                    nCount += 1
                case .del(let t, let on):
                    dlines.append(DiffLine(kind: .deletion, oldNumber: on, newNumber: nil, text: t))
                    if oStart == 0 { oStart = on }
                    oCount += 1
                case .ins(let t, let nn):
                    dlines.append(DiffLine(kind: .insertion, oldNumber: nil, newNumber: nn, text: t))
                    if nStart == 0 { nStart = nn }
                    nCount += 1
                }
            }
            hunks.append(
                DiffHunk(
                    id: hIndex, oldStart: oStart, oldCount: oCount,
                    newStart: nStart, newCount: nCount, lines: dlines))
        }
        return FileDiff(path: path, original: old, hunks: hunks)
    }
}
