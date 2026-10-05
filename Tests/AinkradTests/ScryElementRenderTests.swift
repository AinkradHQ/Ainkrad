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
}
