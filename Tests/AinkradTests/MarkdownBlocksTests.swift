import Foundation
import Testing

@testable import Ainkrad

@Suite("MarkdownBlocks")
struct MarkdownBlocksTests {
    @Test func plainParagraph() {
        #expect(MarkdownBlocks.parse("hello **world**") == [.paragraph("hello **world**")])
    }

    @Test func heading() {
        #expect(MarkdownBlocks.parse("## Title") == [.heading(level: 2, text: "Title")])
    }

    @Test func closedFencedCodeWithLanguage() {
        let src = "```swift\nlet x = 1\n```"
        #expect(MarkdownBlocks.parse(src) == [.codeBlock(language: "swift", code: "let x = 1")])
    }

    @Test func unterminatedFenceStreamsAsCode() {
        let src = "```swift\nlet x = 1"
        #expect(MarkdownBlocks.parse(src) == [.codeBlock(language: "swift", code: "let x = 1")])
    }

    @Test func fenceWithoutLanguage() {
        let src = "```\nraw\n```"
        #expect(MarkdownBlocks.parse(src) == [.codeBlock(language: nil, code: "raw")])
    }

    @Test func bulletList() {
        #expect(MarkdownBlocks.parse("- a\n- b") == [.bulletList(["a", "b"])])
    }

    @Test func orderedList() {
        #expect(MarkdownBlocks.parse("1. a\n2. b") == [.orderedList(["a", "b"])])
    }

    @Test func mixedBlocksSeparatedByBlankLines() {
        let src = "intro\n\n- one\n- two\n\n```\ncode\n```\n\noutro"
        #expect(
            MarkdownBlocks.parse(src) == [
                .paragraph("intro"),
                .bulletList(["one", "two"]),
                .codeBlock(language: nil, code: "code"),
                .paragraph("outro"),
            ])
    }

    @Test func consecutiveTextLinesJoinIntoOneParagraph() {
        #expect(MarkdownBlocks.parse("line one\nline two") == [.paragraph("line one\nline two")])
    }

    @Test func emptyStringIsNoBlocks() {
        #expect(MarkdownBlocks.parse("") == [])
    }

    @Test func thematicBreakDashes() {
        #expect(MarkdownBlocks.parse("---") == [.thematicBreak])
    }

    @Test func thematicBreakAsterisks() {
        #expect(MarkdownBlocks.parse("***") == [.thematicBreak])
    }

    @Test func thematicBreakBetweenParagraphs() {
        #expect(MarkdownBlocks.parse("a\n\n---\n\nb") == [.paragraph("a"), .thematicBreak, .paragraph("b")])
    }

    @Test func bulletNotMistakenForRule() {
        #expect(MarkdownBlocks.parse("- a\n- b") == [.bulletList(["a", "b"])])
    }
}
