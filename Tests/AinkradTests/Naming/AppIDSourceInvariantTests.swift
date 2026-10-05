import Foundation
import Testing

@testable import AinkradHostRuntime

/// Source tripwire: no file may DECLARE a retired app id or publish an MCP tool
/// under a retired prefix.
///
/// Modelled on the test that bans `applicationSupportDirectory` outside
/// `VaultMigration`. The patterns are deliberately narrow — a declaration site,
/// not any mention — so the legitimate survivors need no exemption list:
/// the `"role": "assistant"` provider wire format, the `agent-canvas` and
/// `assistant-appearance` documentIDs, the `pane-canvas` coordinate space, the
/// `<vault>/Assistant/` folder name, and the retired `SettingsPathAliases` keys
/// are all still allowed to say the old words, because none of them declares an
/// app id.
///
/// MUTATION-TESTED: reintroducing `static let id = "files"` anywhere under
/// `Sources/` must make this fail. If it does not, the enumerator is not
/// reaching that file and this test is worthless — which is exactly how a Quest
/// M5 tripwire reported green while inspecting a single line.
@Suite("App id source invariant")
struct AppIDSourceInvariantTests {
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Naming
            .deletingLastPathComponent()  // AinkradTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appending(path: "Sources")
    }

    @Test("no source file declares a retired app id or tool prefix")
    func noRetiredIDs() throws {
        let enumerator = try #require(
            FileManager.default.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }

        #expect(files.count > 100, "found only \(files.count) sources — the path is wrong")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for old in AppIDRenames.map.keys {
                #expect(
                    !source.contains("static let id = \"\(old)\""),
                    "\(file.lastPathComponent) declares the retired app id \"\(old)\"")
                #expect(
                    !source.contains("appID: \"\(old)\""),
                    "\(file.lastPathComponent) builds host services for \"\(old)\"")
                #expect(
                    !source.contains("name: \"\(old)_"),
                    "\(file.lastPathComponent) publishes a tool under the retired \"\(old)_\" prefix")
            }
        }
    }
}
