import Foundation
import Testing
@testable import Ainkrad

@Suite("MarkdownStreamParser")
struct MarkdownStreamParserTests {

    /// Feeds `source` through the parser one delta at a time and asserts the
    /// result matches the batch parser at EVERY prefix — not just at the end.
    /// A parser that is only right once the stream finishes is useless: the
    /// whole point is what the user sees mid-reply.
    private func assertMatchesBatch(_ source: String, chunkSize: Int,
                                    sourceLocation: SourceLocation = #_sourceLocation) {
        var parser = MarkdownStreamParser()
        var fed = ""
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            let end = min(index + chunkSize, characters.count)
            let delta = String(characters[index..<end])
            parser.append(delta)
            fed += delta
            #expect(parser.blocks == MarkdownBlocks.parse(fed),
                    "diverged after \(fed.count) chars of \(source.count)",
                    sourceLocation: sourceLocation)
            #expect(parser.text == fed, sourceLocation: sourceLocation)
            index = end
        }
    }

    @Test func emptyStreamHasNoBlocks() {
        let parser = MarkdownStreamParser()
        #expect(parser.blocks.isEmpty)
        #expect(parser.text.isEmpty)
    }

    @Test func singleParagraphOneCharacterAtATime() {
        assertMatchesBatch("hello **world**", chunkSize: 1)
    }

    @Test func paragraphsSeparatedByBlankLines() {
        assertMatchesBatch("first para\n\nsecond para\n\nthird", chunkSize: 1)
    }

    @Test func headingsAndProse() {
        assertMatchesBatch("# Title\n\nbody text\n\n## Sub\n\nmore", chunkSize: 1)
    }

    @Test func bulletListThenProse() {
        assertMatchesBatch("- a\n- b\n- c\n\nafter", chunkSize: 1)
    }

    @Test func orderedListThenProse() {
        assertMatchesBatch("1. a\n2. b\n\nafter", chunkSize: 1)
    }

    /// The dangerous case: a blank line INSIDE a fence must NOT become a commit
    /// point, or the fence is split in half and renders as two code blocks.
    @Test func blankLineInsideAFenceIsNotACommitPoint() {
        assertMatchesBatch("```swift\nlet a = 1\n\nlet b = 2\n```\n\nafter", chunkSize: 1)
    }

    @Test func unterminatedFenceStreamsAsCode() {
        assertMatchesBatch("intro\n\n```swift\nlet x = 1", chunkSize: 1)
    }

    @Test func thematicBreakBetweenParagraphs() {
        assertMatchesBatch("before\n\n---\n\nafter", chunkSize: 1)
    }

    @Test func trailingBlankLines() {
        assertMatchesBatch("para\n\n\n\n", chunkSize: 1)
    }

    @Test func multiCharacterChunksMatchToo() {
        let source = "# H\n\ntext with **bold**\n\n- one\n- two\n\n```\ncode\n\nmore\n```\n\nend"
        for chunk in [1, 2, 3, 5, 7, 13] {
            assertMatchesBatch(source, chunkSize: chunk)
        }
    }

    /// A delta that lands mid-fence-marker (e.g. "`" then "``") must not be
    /// mistaken for an open fence.
    @Test func fenceMarkerSplitAcrossDeltas() {
        assertMatchesBatch("a\n\n```\nx\n```\n\nb", chunkSize: 1)
    }

    @Test func resetClearsEverything() {
        var parser = MarkdownStreamParser()
        parser.append("# Title\n\nbody")
        parser.reset()
        #expect(parser.blocks.isEmpty)
        #expect(parser.text.isEmpty)
    }

    /// Differential fuzz: random markdown-ish documents, random chunking.
    /// This is the test that actually proves the commit-point property; the
    /// hand-written cases above only pin the shapes we thought of.
    @Test func fuzzMatchesBatchParserForRandomDocuments() {
        var rng = SystemRandomNumberGenerator()
        let fragments = ["para text ", "**bold** ", "`code` ", "\n", "\n\n",
                         "# Head\n", "## Sub\n", "- item\n", "1. item\n",
                         "```\n", "```swift\n", "---\n", "   ", "\t"]
        for _ in 0..<300 {
            var source = ""
            for _ in 0..<Int.random(in: 1...40, using: &rng) {
                source += fragments.randomElement(using: &rng)!
            }
            assertMatchesBatch(source, chunkSize: Int.random(in: 1...6, using: &rng))
        }
    }
}
