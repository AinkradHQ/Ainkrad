import Testing

@testable import Ainkrad

@Suite("FileGlyph")
struct FileGlyphTests {
    @Test func swiftFile() { #expect(FileGlyph.symbol(forPath: "Sources/App.swift") == "swift") }

    @Test func markdown() {
        #expect(FileGlyph.symbol(forPath: "README.md") == "doc.richtext")
        #expect(FileGlyph.symbol(forPath: "notes.markdown") == "doc.richtext")
    }

    @Test func dataFiles() {
        #expect(FileGlyph.symbol(forPath: "project.yml") == "curlybraces")
        #expect(FileGlyph.symbol(forPath: "config.json") == "curlybraces")
        #expect(FileGlyph.symbol(forPath: "Info.plist") == "curlybraces")
    }

    @Test func codeFiles() {
        #expect(FileGlyph.symbol(forPath: "index.ts") == "chevron.left.forwardslash.chevron.right")
        #expect(FileGlyph.symbol(forPath: "main.py") == "chevron.left.forwardslash.chevron.right")
    }

    @Test func imagesCaseInsensitive() { #expect(FileGlyph.symbol(forPath: "logo.PNG") == "photo") }

    @Test func pdf() { #expect(FileGlyph.symbol(forPath: "spec.pdf") == "doc.text.fill") }

    @Test func unknownExtensionFallsBack() { #expect(FileGlyph.symbol(forPath: "data.xyz") == "doc.text") }

    @Test func noExtensionFallsBack() { #expect(FileGlyph.symbol(forPath: "Makefile") == "doc.text") }

    @Test func dotfileHasNoExtension() { #expect(FileGlyph.symbol(forPath: ".gitignore") == "doc.text") }
}
