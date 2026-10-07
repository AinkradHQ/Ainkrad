import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

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

    /// `rows(from:)` split for `AinkradDataTable`: the first row is the
    /// header, the rest are body rows, and every row is padded with empty
    /// cells to the widest row so a short row never loses a column.
    static func table(from body: String) -> (header: [String], rows: [ScryTableRow]) {
        let parsed = rows(from: body)
        let width = parsed.map(\.count).max() ?? 0
        let padded = parsed.map { $0 + Array(repeating: "", count: width - $0.count) }
        guard let header = padded.first else { return ([], []) }
        let dataRows = padded.dropFirst().enumerated().map { ScryTableRow(id: $0.offset, cells: $0.element) }
        return (header, dataRows)
    }
}

/// One body row of a Scry table, keyed by its position.
struct ScryTableRow: Identifiable, Equatable {
    let id: Int
    let cells: [String]
}

/// `.table` — a markdown pipe table or CSV body drawn as the kit data table,
/// its first row the header.
@MainActor
struct ScryTableCard: View {
    let element: ScryElement

    var body: some View {
        let table = ScryTableParse.table(from: element.body)
        if !table.header.isEmpty {
            AinkradDataTable(
                rows: table.rows,
                columns: table.header.indices.map { i in
                    AinkradTableColumn(id: String(i), title: table.header[i]) { $0.cells[i] }
                })
        }
    }
}
