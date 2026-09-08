import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Pure table-body → rows parser (markdown pipe table or CSV). Unit-tested.
/// Detects the separator from the body (`|` wins over `,`), then drops a
/// markdown separator row (all-dash cells) so header/data rows line up.
enum ScryTableParse {
    static func rows(from body: String) -> [[String]] {
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }
        let sep: Character = body.contains("|") ? "|" : ","
        return lines.compactMap { line -> [String]? in
            let cells = line.split(separator: sep, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // Drop a markdown separator row (every cell is all dashes).
            if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 == "-" } }) { return nil }
            return cells
        }
    }
}

/// `.table` — a markdown pipe table or CSV body rendered as rows.
@MainActor
struct ScryTableCard: View {
    let element: ScryElement
    let tokens: DesignTokens

    var body: some View {
        let rows = ScryTableParse.rows(from: element.body)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(AinkradFont.mono(11))
                            .foregroundStyle(tokens.foreground.opacity(i == 0 ? 0.9 : 0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
