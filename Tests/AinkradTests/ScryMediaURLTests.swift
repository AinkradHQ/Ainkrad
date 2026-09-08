import Foundation
import Testing
@testable import Ainkrad

@Suite("ScryMediaURL")
struct ScryMediaURLTests {
    @Test("an http url is playable")
    func httpAllowed() {
        #expect(ScryMediaURL.playable("https://example.com/a.mp4") != nil)
    }

    @Test("a file url for a file that exists is playable")
    func existingFileAllowed() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scry-\(UUID().uuidString).mp4")
        try Data([0x00]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(ScryMediaURL.playable(tmp.absoluteString) != nil)
    }

    @Test("a file url for a missing file is rejected, not handed to AVPlayer")
    func missingFileRejected() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scry-does-not-exist-\(UUID().uuidString).mp4")
        #expect(ScryMediaURL.playable(missing.absoluteString) == nil)
    }

    @Test("junk and unsupported schemes are rejected")
    func junkRejected() {
        #expect(ScryMediaURL.playable("") == nil)
        #expect(ScryMediaURL.playable("not a url at all") == nil)
        #expect(ScryMediaURL.playable("javascript:alert(1)") == nil)
    }
}
