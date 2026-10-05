import Testing

@testable import Ainkrad

@Suite struct MentionContentResolverTests {
    @Test func embedAppendsLabeledBlock() {
        let out = MentionContentResolver.augment(
            text: "explain @/proj/a.swift please",
            mentions: [ComposerMention(path: "/proj/a.swift", mode: .embed)],
            read: { $0 == "/proj/a.swift" ? "let x = 1" : nil }
        )
        #expect(out.hasPrefix("explain @/proj/a.swift please"))
        #expect(out.contains("<mentioned_files>"))
        #expect(out.contains("### /proj/a.swift"))
        #expect(out.contains("let x = 1"))
        #expect(out.contains("</mentioned_files>"))
    }

    @Test func referenceModeIsNotEmbedded() {
        let out = MentionContentResolver.augment(
            text: "see @/proj/a.swift",
            mentions: [ComposerMention(path: "/proj/a.swift", mode: .reference)],
            read: { _ in "SHOULD NOT APPEAR" }
        )
        #expect(out == "see @/proj/a.swift")
    }

    @Test func unreadableEmbedFallsBackToPathOnly() {
        let out = MentionContentResolver.augment(
            text: "see @/proj/bin.o",
            mentions: [ComposerMention(path: "/proj/bin.o", mode: .embed)],
            read: { _ in nil }  // binary / oversize / missing
        )
        #expect(out == "see @/proj/bin.o")
    }

    @Test func multipleEmbedsEachGetOwnSection() {
        let out = MentionContentResolver.augment(
            text: "diff @/a @/b",
            mentions: [
                ComposerMention(path: "/a", mode: .embed),
                ComposerMention(path: "/b", mode: .embed),
            ],
            read: { $0 == "/a" ? "AA" : "BB" }
        )
        #expect(out.contains("### /a\nAA"))
        #expect(out.contains("### /b\nBB"))
    }
}
