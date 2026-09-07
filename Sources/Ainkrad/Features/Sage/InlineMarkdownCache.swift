import Foundation

/// Memoises `AttributedString(markdown:)` for transcript inline text.
///
/// `SageMarkdownText` resolved inline markdown on EVERY body evaluation, and the
/// streaming transcript re-evaluates many times a second. The source strings are
/// overwhelmingly repeats — a paragraph that finished streaming ten seconds ago
/// is re-resolved on every subsequent frame — so a cache turns per-frame work
/// into per-distinct-block work.
///
/// `NSCache` rather than a dictionary: it evicts under memory pressure on its
/// own, which matters because a long session's transcript is unbounded. The
/// count limit is a second bound for the ordinary case.
///
/// The cache key is the source string alone. Safe because callers apply font
/// and colour to the resulting `Text`, not to the `AttributedString` — if that
/// ever changes, this key must grow to include the styling.
enum InlineMarkdownCache {
    private final class Box: NSObject {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    // NSCache is internally thread-safe; only Swift's static-analysis of
    // "may have shared mutable state" objects here, not an actual data race.
    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 2_000
        return cache
    }()

    /// Tracked separately: `NSCache` deliberately exposes no count.
    private static let countLock = NSLock()
    nonisolated(unsafe) private static var keys: Set<String> = []

    static func attributed(_ source: String) -> AttributedString {
        let key = source as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        // Never throws into the view: an unparseable fragment renders as its
        // raw source, which is what the previous `try?` fallback did.
        let value = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        cache.setObject(Box(value), forKey: key)
        countLock.withLock { _ = keys.insert(source) }
        return value
    }

    static func clear() {
        cache.removeAllObjects()
        countLock.withLock { keys.removeAll() }
    }

    static var countForTesting: Int {
        countLock.withLock { keys.count }
    }
}
