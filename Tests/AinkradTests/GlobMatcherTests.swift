import Testing

@testable import Ainkrad

@Suite("GlobMatcher")
struct GlobMatcherTests {
    @Test func star() {
        #expect(GlobMatcher.matches("Foo.swift", pattern: "*.swift"))
        #expect(!GlobMatcher.matches("a/Foo.swift", pattern: "*.swift"))
    }
    @Test func globstar() {
        #expect(GlobMatcher.matches("a/b/Foo.swift", pattern: "**/*.swift"))
        #expect(GlobMatcher.matches("Foo.swift", pattern: "**/*.swift"))
    }
    @Test func question() {
        #expect(GlobMatcher.matches("a.txt", pattern: "?.txt"))
        #expect(!GlobMatcher.matches("ab.txt", pattern: "?.txt"))
    }
    @Test func dotIsLiteral() {
        #expect(!GlobMatcher.matches("axswift", pattern: "*.swift"))
    }
}
