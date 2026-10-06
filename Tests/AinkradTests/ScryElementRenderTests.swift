import Foundation
import Testing

@testable import Ainkrad

@Suite("ScryTableParse")
struct ScryElementRenderTests {
    @Test func parsesMarkdownTableSkippingSeparator() {
        let body = """
            Name | Role
            --- | ---
            Ada | Eng
            Bo | PM
            """
        let rows = ScryTableParse.rows(from: body)
        #expect(rows.count == 3)  // header + 2 data rows (separator dropped)
        #expect(rows.first == ["Name", "Role"])
        #expect(rows.last == ["Bo", "PM"])
    }

    @Test func parsesCSVFallback() {
        let rows = ScryTableParse.rows(from: "a,b,c\n1,2,3")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func emptyBodyGivesNoRows() {
        #expect(ScryTableParse.rows(from: "").isEmpty)
    }

    @Test func tableSplitsHeaderAndPadsShortRows() {
        let table = ScryTableParse.table(from: "a,b,c\n1,2\n3,4,5")
        #expect(table.header == ["a", "b", "c"])
        #expect(table.rows == [ScryTableRow(id: 0, cells: ["1", "2", ""]), ScryTableRow(id: 1, cells: ["3", "4", "5"])])
    }

    @Test func tableWidensTheHeaderToTheWidestRow() {
        let table = ScryTableParse.table(from: "a,b\n1,2,3")
        #expect(table.header == ["a", "b", ""])
        #expect(table.rows.map(\.cells) == [["1", "2", "3"]])
    }

    @Test func headerOnlyAndEmptyBodies() {
        #expect(ScryTableParse.table(from: "a,b").header == ["a", "b"])
        #expect(ScryTableParse.table(from: "a,b").rows.isEmpty)
        #expect(ScryTableParse.table(from: "").header.isEmpty)
    }
}
