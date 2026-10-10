import AinkradHostRuntime
import Foundation
import Testing

@testable import AinkradHostRuntime

/// Glass Native E4.1: `host.language.island` picks the home island; a file
/// without it (and every older host) reads `islandArt`.
@Suite("Glass island language")
struct GlassIslandLanguageTests {
    private func resolve(_ language: String) throws -> (home: HomeLanguage, problems: [String]) {
        let section = try JSONDecoder().decode(LanguageSection.self, from: Data(language.utf8))
        return HomeLanguage.resolve(section)
    }

    @Test("island glass wins over islandArt")
    func glassWins() throws {
        let result = try resolve(#"{"id": "glass", "island": "glass", "islandArt": false}"#)
        #expect(result.home.island == .glass)
        #expect(!result.home.islandArt)
        #expect(result.problems.isEmpty)
    }

    @Test("without island, islandArt decides: art or the brand mark")
    func legacy() throws {
        #expect(try resolve(#"{"id": "a"}"#).home.island == .art)
        #expect(try resolve(#"{"id": "b", "islandArt": false}"#).home.island == .mark)
        #expect(HomeLanguage.neon.island == .art)
    }

    @Test("an unknown island falls back to the islandArt reading, with a warning")
    func unknown() throws {
        let result = try resolve(#"{"id": "c", "island": "volcano", "islandArt": false}"#)
        #expect(result.home.island == .mark)
        #expect(result.problems.contains { $0.hasPrefix("island 'volcano'") })
    }
}
