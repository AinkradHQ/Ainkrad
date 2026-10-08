import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("DebugGalleryArguments")
struct DebugGalleryArgumentsTests {
    // MARK: - AinkradOpenGallery
    @Test("returns false when -AinkradOpenGallery is absent")
    func absentOpenGallery() {
        let args: [String: String] = [:]
        let lookup: ArgumentLookup = { args[$0] }
        #expect(!parseDebugOpenGalleryArgument(lookup))
    }

    @Test("returns false when -AinkradOpenGallery is invalid value")
    func invalidOpenGallery() {
        let args = ["AinkradOpenGallery": "0"]
        let lookup: ArgumentLookup = { args[$0] }
        #expect(!parseDebugOpenGalleryArgument(lookup))
    }

    @Test("returns true when -AinkradOpenGallery is 1 or true")
    func validOpenGallery() {
        let args1 = ["AinkradOpenGallery": "1"]
        let lookup1: ArgumentLookup = { args1[$0] }
        #expect(parseDebugOpenGalleryArgument(lookup1))

        let args2 = ["AinkradOpenGallery": "true"]
        let lookup2: ArgumentLookup = { args2[$0] }
        #expect(parseDebugOpenGalleryArgument(lookup2))

        let args3 = ["AinkradOpenGallery": " TRUE "]
        let lookup3: ArgumentLookup = { args3[$0] }
        #expect(parseDebugOpenGalleryArgument(lookup3))
    }

    // MARK: - AinkradGalleryTheme
    private let known = Set(neonSchemeIDs)

    @Test("returns nil when -AinkradGalleryTheme is absent or empty")
    func absentOrEmptyTheme() {
        let emptyDict: [String: String] = [:]
        let lookup1: ArgumentLookup = { emptyDict[$0] }
        #expect(parseDebugGalleryThemeArgument(lookup1, knownSchemeIDs: known) == nil)

        let whitespaceDict = ["AinkradGalleryTheme": "  "]
        let lookup2: ArgumentLookup = { whitespaceDict[$0] }
        #expect(parseDebugGalleryThemeArgument(lookup2, knownSchemeIDs: known) == nil)
    }

    @Test("returns the scheme id for a known old theme id")
    func validTheme() {
        let args1 = ["AinkradGalleryTheme": "neonBlue"]
        let lookup1: ArgumentLookup = { args1[$0] }
        #expect(parseDebugGalleryThemeArgument(lookup1, knownSchemeIDs: known) == "neonBlue")

        let args2 = ["AinkradGalleryTheme": "cyberPurple"]
        let lookup2: ArgumentLookup = { args2[$0] }
        #expect(parseDebugGalleryThemeArgument(lookup2, knownSchemeIDs: known) == "cyberPurple")
    }

    @Test("returns nil for unknown theme ID")
    func unknownTheme() {
        let args = ["AinkradGalleryTheme": "nonexistentTheme"]
        let lookup: ArgumentLookup = { args[$0] }
        #expect(parseDebugGalleryThemeArgument(lookup, knownSchemeIDs: known) == nil)
    }

    // MARK: - AinkradGallerySection
    @Test("returns nil when -AinkradGallerySection is absent or empty")
    func absentOrEmptySection() {
        let emptyDict: [String: String] = [:]
        let lookup1: ArgumentLookup = { emptyDict[$0] }
        #expect(parseDebugGallerySectionArgument(lookup1) == nil)

        let whitespaceDict = ["AinkradGallerySection": "  "]
        let lookup2: ArgumentLookup = { whitespaceDict[$0] }
        #expect(parseDebugGallerySectionArgument(lookup2) == nil)
    }

    @Test("returns section id when valid")
    func validSection() {
        let args1 = ["AinkradGallerySection": "foundation"]
        let lookup1: ArgumentLookup = { args1[$0] }
        #expect(parseDebugGallerySectionArgument(lookup1) == "foundation")

        let args2 = ["AinkradGallerySection": " wave5 "]
        let lookup2: ArgumentLookup = { args2[$0] }
        #expect(parseDebugGallerySectionArgument(lookup2) == "wave5")
    }
}
