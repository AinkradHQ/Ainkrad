import Foundation
import Testing
@testable import Ainkrad

/// Pins the ownership invariant that used to be broken twice (once before
/// AVKit was even linked, once after): a media card keeps ONE player per URL
/// and only rebuilds when the URL actually changes — never on every render.
@Suite("MediaPlayerOwnership")
struct MediaPlayerOwnershipTests {
    private final class FakePlayer {
        let id = UUID()
    }

    @Test("no current player and a url: builds one")
    func buildsWhenNone() {
        let url = URL(string: "https://example.com/a.mp4")!
        var buildCount = 0
        let result = MediaPlayerOwnership.resolve(current: nil, url: url) { _ in
            buildCount += 1
            return FakePlayer()
        }
        #expect(result?.url == url)
        #expect(buildCount == 1)
    }

    @Test("same url as current: keeps the existing player, does not rebuild")
    func keepsWhenURLUnchanged() {
        let url = URL(string: "https://example.com/a.mp4")!
        let existing = FakePlayer()
        var buildCount = 0
        let result = MediaPlayerOwnership.resolve(current: (url, existing), url: url) { _ in
            buildCount += 1
            return FakePlayer()
        }
        #expect(result?.player === existing)
        #expect(buildCount == 0)
    }

    @Test("url changed: builds a new player, drops the old one")
    func rebuildsWhenURLChanges() {
        let oldURL = URL(string: "https://example.com/a.mp4")!
        let newURL = URL(string: "https://example.com/b.mp4")!
        let existing = FakePlayer()
        var buildCount = 0
        let result = MediaPlayerOwnership.resolve(current: (oldURL, existing), url: newURL) { _ in
            buildCount += 1
            return FakePlayer()
        }
        #expect(result?.url == newURL)
        #expect(result?.player !== existing)
        #expect(buildCount == 1)
    }

    @Test("nil url: no player, regardless of current state")
    func nilURLClearsPlayer() {
        let existing = FakePlayer()
        let url = URL(string: "https://example.com/a.mp4")!
        let result = MediaPlayerOwnership.resolve(current: (url, existing), url: nil) { _ in FakePlayer() }
        #expect(result == nil)
    }

    /// The exact churn the crash report was full of: a hover-driven re-render
    /// with the same URL, over and over, must never allocate a new player.
    @Test("repeated resolve calls with an unchanged url never rebuild")
    func repeatedResolveIsStable() {
        let url = URL(string: "https://example.com/a.mp4")!
        var current: (url: URL, player: FakePlayer)?
        var buildCount = 0
        for _ in 0..<50 {
            current = MediaPlayerOwnership.resolve(current: current, url: url) { _ in
                buildCount += 1
                return FakePlayer()
            }
        }
        #expect(buildCount == 1)
    }
}
