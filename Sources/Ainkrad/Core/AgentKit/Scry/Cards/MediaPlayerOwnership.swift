import Foundation

/// Decides whether a media card should keep its existing player or build a
/// new one, given the URL it should now be playing. Pulled out of
/// `ScryMediaCard`/`GeneratedVideoView`'s `.task(id:)` bodies so the
/// invariant — one player per card per URL, not one per render — is testable
/// on its own, without standing up an `AVPlayer` (which needs real media I/O)
/// or a live view hierarchy.
///
/// This is the exact defect class that shipped twice before AVKit was even
/// linked: a fresh player built inside `body` on every hover/drag frame.
enum MediaPlayerOwnership {
    /// - Parameters:
    ///   - current: the card's existing (url, player) pair, if it has one.
    ///   - url: the URL the card should be playing now (`nil` if unplayable).
    ///   - make: builds a new player for a URL. Called only when a new player
    ///     is actually needed.
    /// - Returns: `current` unchanged when its URL already matches `url`
    ///   (avoiding a rebuild); a freshly made pair when the URL changed or
    ///   there was no current player; `nil` when `url` is `nil`.
    static func resolve<Player: AnyObject>(
        current: (url: URL, player: Player)?,
        url: URL?,
        make: (URL) -> Player
    ) -> (url: URL, player: Player)? {
        guard let url else { return nil }
        if let current, current.url == url { return current }
        return (url, make(url))
    }
}
