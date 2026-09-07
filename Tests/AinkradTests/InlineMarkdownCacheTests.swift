import Foundation
import Testing
@testable import Ainkrad

@Suite("InlineMarkdownCache", .serialized)
struct InlineMarkdownCacheTests {

    @Test func resolvesInlineBold() {
        InlineMarkdownCache.clear()
        let result = InlineMarkdownCache.attributed("hello **world**")
        #expect(String(result.characters) == "hello world")
    }

    @Test func repeatedLookupsReturnAnEqualValue() {
        InlineMarkdownCache.clear()
        let first = InlineMarkdownCache.attributed("a *b* c")
        let second = InlineMarkdownCache.attributed("a *b* c")
        #expect(first == second)
    }

    @Test func distinctSourcesProduceDistinctEntries() {
        InlineMarkdownCache.clear()
        _ = InlineMarkdownCache.attributed("one")
        _ = InlineMarkdownCache.attributed("two")
        #expect(InlineMarkdownCache.countForTesting == 2)
    }

    @Test func theSameSourceIsStoredOnce() {
        InlineMarkdownCache.clear()
        for _ in 0..<50 { _ = InlineMarkdownCache.attributed("same") }
        #expect(InlineMarkdownCache.countForTesting == 1)
    }

    @Test func whitespaceIsPreservedAsTheRendererExpects() {
        InlineMarkdownCache.clear()
        // .inlineOnlyPreservingWhitespace is what SageMarkdownText used; losing
        // it would silently collapse indentation in the transcript.
        let result = InlineMarkdownCache.attributed("a    b")
        #expect(String(result.characters) == "a    b")
    }

    @Test func unparseableSourceFallsBackToPlainTextRatherThanThrowing() {
        InlineMarkdownCache.clear()
        let weird = "[unclosed(("
        let result = InlineMarkdownCache.attributed(weird)
        #expect(String(result.characters).contains("unclosed"))
    }

    @Test func clearEmptiesTheCache() {
        InlineMarkdownCache.clear()
        _ = InlineMarkdownCache.attributed("x")
        InlineMarkdownCache.clear()
        #expect(InlineMarkdownCache.countForTesting == 0)
    }
}
