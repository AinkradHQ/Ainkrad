import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@Suite("Generated media wiring")
@MainActor
struct GeneratedMediaWiringTests {
    /// Generated media is irreplaceable — re-running a prompt yields different
    /// output — so it belongs in the vault, not the cache.
    @Test func mediaIsWrittenIntoTheVault() throws {
        let t = TestHome.make("media")
        defer { t.cleanup() }

        let store = GeneratedMediaStore(baseDirectory: t.home.shared(.media))
        let url = try store.write(Data([0x1, 0x2]), fileExtension: "png", id: "fixed")

        #expect(url.path.hasPrefix(t.home.vaultRoot.path))
        #expect(!url.path.hasPrefix(t.home.cacheRoot.path))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
