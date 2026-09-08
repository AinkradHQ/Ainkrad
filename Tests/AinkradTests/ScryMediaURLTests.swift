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

    /// Guards `ScryMediaCard.swift`'s `scryAVKitLinkAnchor`: a hard reference to
    /// an AVKit ObjC class that exists solely to force the linker to bind
    /// AVKit.framework. Swift emits no unused-constant warning for an unused
    /// `private let`, so a future cleanup could delete that anchor silently —
    /// and the app would abort on the very first `VideoPlayer` it constructs
    /// (SwiftUI's `VideoPlayer` shim subclasses AVKit's `AVPlayerView`). If
    /// this test ever fails, AVKit is not in the load commands: go re-add the
    /// anchor before doing anything else.
    @Test("AVKit is actually linked into the app")
    func avKitIsLinked() {
        #expect(NSClassFromString("AVPlayerView") != nil)
    }
}
