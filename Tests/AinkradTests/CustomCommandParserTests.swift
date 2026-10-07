import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomCommandParser")
struct CustomCommandParserTests {
    @Test func parsesBodyWithNoFrontMatter() {
        let cmd = CustomCommandParser.parse("Do the thing with $ARGUMENTS", name: "doit", scope: .user)
        #expect(cmd.name == "doit")
        #expect(cmd.scope == .user)
        #expect(cmd.description.isEmpty)
        #expect(cmd.argumentHint.isEmpty)
        #expect(cmd.body == "Do the thing with $ARGUMENTS")
    }

    @Test func parsesOptionalFrontMatter() {
        let text = "---\ndescription: Ship a release\nargument-hint: <version>\n---\nRelease $1 now"
        let cmd = CustomCommandParser.parse(text, name: "release", scope: .project)
        #expect(cmd.description == "Ship a release")
        #expect(cmd.argumentHint == "<version>")
        #expect(cmd.body == "Release $1 now")
        #expect(cmd.scope == .project)
    }

    @Test func malformedFrontMatterFallsBackToWholeBody() {
        // Opening "---" with no closing fence: treat the entire file as body,
        // never throw (files may be hand-edited).
        let text = "---\ndescription: broken\nRelease now"
        let cmd = CustomCommandParser.parse(text, name: "release", scope: .user)
        #expect(cmd.description.isEmpty)
        #expect(cmd.body == text)
    }
}
