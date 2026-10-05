import Foundation
import Testing

@testable import Ainkrad

@Suite("FileChangeWatcher glob")
struct FileChangeWatcherTests {
    @Test func nilGlobMatchesEverything() {
        #expect(GlobMatcher.matches("/repo/a.txt", glob: nil))
    }
    @Test func globMatchesExtension() {
        #expect(GlobMatcher.matches("/repo/src/Foo.swift", glob: "*.swift"))
        #expect(!GlobMatcher.matches("/repo/src/Foo.txt", glob: "*.swift"))
    }
    @Test func globMatchesBasename() {
        #expect(GlobMatcher.matches("/repo/Makefile", glob: "Makefile"))
    }
}
