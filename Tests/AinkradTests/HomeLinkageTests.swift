import AinkradAppKit
import Foundation
import Testing

@Suite("AinkradHome linkage")
struct HomeLinkageTests {
    /// Proves the host is pinned to an AinkradAppKit revision that carries
    /// AinkradAppKitHome — a stale pin fails here rather than in bootstrap.
    @Test func homeTypesAreVisibleFromTheHost() {
        let home = Home(
            vaultRoot: URL(fileURLWithPath: "/tmp/v"),
            cacheRoot: URL(fileURLWithPath: "/tmp/c"))
        #expect(home.shared(.config).path == "/tmp/v/Config")
        #expect(home.vault(app: AppID("Lore")).path == "/tmp/v/Apps/Lore")
    }
}
