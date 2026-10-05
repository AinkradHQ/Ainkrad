import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillParser")
struct SkillParserTests {
    private let valid = """
        ---
        name: pdf-processing
        description: Extract text, tables, and forms from PDF files
        allowed-tools: read_file, run_terminal
        triggers:
          - pdf
          - "extract from a document"
        ---
        # PDF Processing

        1. Read the file.
        2. Extract with pdftotext.
        """

    @Test func parsesFrontMatterAndBody() throws {
        let s = try SkillParser.parse(valid, source: .local)
        #expect(s.name == "pdf-processing")
        #expect(s.description == "Extract text, tables, and forms from PDF files")  // comma-safe scalar
        #expect(s.allowedTools == ["read_file", "run_terminal"])
        #expect(s.triggers == ["pdf", "extract from a document"])  // unquoted dashed list
        #expect(s.source == .local)
        #expect(s.body.hasPrefix("# PDF Processing"))
        #expect(s.body.contains("pdftotext"))
    }

    @Test func throwsWhenNoFrontMatter() {
        #expect(throws: SkillParseError.self) {
            _ = try SkillParser.parse("# just a heading\nno front matter", source: .local)
        }
    }

    @Test func throwsWhenMissingName() {
        let text = "---\ndescription: has description only\n---\nbody"
        #expect(throws: SkillParseError.missingName) {
            _ = try SkillParser.parse(text, source: .local)
        }
    }

    @Test func throwsWhenMissingDescription() {
        let text = "---\nname: only-name\n---\nbody"
        #expect(throws: SkillParseError.missingDescription) {
            _ = try SkillParser.parse(text, source: .local)
        }
    }

    @Test func inlineBracketListParses() throws {
        let text = "---\nname: n\ndescription: d\nallowed-tools: [read_file, edit_file]\n---\nbody"
        let s = try SkillParser.parse(text, source: .marketplace)
        #expect(s.allowedTools == ["read_file", "edit_file"])
    }

    @Test func handlesCRLFLineEndings() throws {
        let text = "---\r\nname: crlf\r\ndescription: windows file\r\n---\r\nbody line"
        let s = try SkillParser.parse(text, source: .local)
        #expect(s.name == "crlf")
        #expect(s.body == "body line")
    }

    // MARK: - Robustness (untrusted input) — must never crash.

    @Test func emptyFileThrowsMissingFrontMatter() {
        #expect(throws: SkillParseError.missingFrontMatter) {
            _ = try SkillParser.parse("", source: .local)
        }
    }

    @Test func whitespaceOnlyFileThrowsMissingFrontMatter() {
        #expect(throws: SkillParseError.missingFrontMatter) {
            _ = try SkillParser.parse("   \n\t\n   ", source: .local)
        }
    }

    @Test func garbageBinaryLikeTextThrowsMissingFrontMatter() {
        // Non-front-matter garbage should be a captured error, not a crash.
        let garbage = "\u{0}\u{1}\u{2} random \\xFF bytes-as-escaped-text ---not-really---"
        #expect(throws: SkillParseError.self) {
            _ = try SkillParser.parse(garbage, source: .local)
        }
    }

    @Test func malformedDelimiterOnlyOneDashLineThrows() {
        // Only a single `---` present (no closing delimiter) must not hang/crash.
        let text = "---\nname: n\ndescription: d\nno closing delimiter here"
        #expect(throws: SkillParseError.missingFrontMatter) {
            _ = try SkillParser.parse(text, source: .local)
        }
    }

    @Test func tripleDashInsideBodyDoesNotConfuseParsing() throws {
        let text = """
            ---
            name: has-body-delimiters
            description: body contains its own --- markers
            ---
            Section one.

            ---

            Section two, after a body-internal delimiter.
            ---
            Section three.
            """
        let s = try SkillParser.parse(text, source: .local)
        #expect(s.name == "has-body-delimiters")
        #expect(s.body.contains("Section one."))
        #expect(s.body.contains("Section two"))
        #expect(s.body.contains("Section three."))
        // Only the FIRST `---` block is front matter; the rest stays in body.
        #expect(s.body.contains("---"))
    }

    @Test func hugeFileParsesWithoutCrashOrHang() throws {
        let bigBody = String(repeating: "line of body text\n", count: 200_000)
        let text = "---\nname: huge\ndescription: a very large body\n---\n\(bigBody)"
        let s = try SkillParser.parse(text, source: .local)
        #expect(s.name == "huge")
        #expect(s.body.hasPrefix("line of body text"))
    }

    @Test func weirdWhitespaceAroundKeysAndValuesIsTolerated() throws {
        let text = "---\n   name:    padded-name   \n description :  padded description  \n---\nbody"
        let s = try SkillParser.parse(text, source: .local)
        #expect(s.name == "padded-name")
        #expect(s.description == "padded description")
    }

    @Test func parseFrontMatterIsPureAndDeterministic() {
        let yaml = "name: n\ntriggers:\n  - a\n  - b\n"
        let first = SkillParser.parseFrontMatter(yaml)
        let second = SkillParser.parseFrontMatter(yaml)
        #expect(first == second)
        #expect(first["triggers"] == ["a", "b"])
    }
}
