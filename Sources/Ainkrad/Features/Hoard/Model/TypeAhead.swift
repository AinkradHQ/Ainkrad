import Foundation

/// How long a typed prefix stays alive before the next keystroke starts a new
/// one. Matches the platform convention closely enough that muscle memory from
/// Finder transfers.
let typeAheadTimeout: TimeInterval = 0.8

/// Where the cursor should land for a typed prefix, or `nil` for no match.
///
/// Prefix matching, not fuzzy: type-to-select is a jump, and `/` and ⌘P already
/// own fuzzy search. Someone typing "re" expects "readme.md", not the highest
/// scoring name containing an r and an e.
///
/// Search WRAPS from `from`, so repeatedly typing the same prefix cycles
/// through every match instead of sticking on the first one — the behaviour
/// that makes type-ahead usable in a folder with twelve `image-*.png`.
func typeAheadIndex(
    in names: [String], matching query: String,
    from startIndex: Int
) -> Int? {
    guard !query.isEmpty, !names.isEmpty else { return nil }
    let needle = query.lowercased()

    for offset in 0..<names.count {
        let index = (startIndex + offset) % names.count
        if names[index].lowercased().hasPrefix(needle) { return index }
    }
    return nil
}

/// What a keystroke means for the cursor.
enum TypeAheadStep: Equatable {
    /// A new or extended prefix — search from the top of the listing.
    case search(String)
    /// The same single letter again — advance to the NEXT match instead.
    case nextMatch(String)
}

/// The accumulated prefix and when it was last touched.
///
/// A value type: the timing decision ("is this keystroke continuing the last
/// word or starting a new one?") is pure arithmetic on a timestamp, so it can
/// be tested without a view or a clock.
struct TypeAheadBuffer: Equatable {
    private(set) var query = ""
    private(set) var lastKeystroke: Date = .distantPast

    /// Appends `character`, or starts over if the previous keystroke aged out.
    ///
    /// Repeating the same single letter deliberately does NOT extend the query:
    /// `aa` almost never names a file, while pressing `a` twice to reach the
    /// second `a…` entry is the common intent. Leaving the buffer at one letter
    /// is what lets a third and fourth press keep cycling instead of searching
    /// for `aaa`.
    mutating func append(_ character: Character, at now: Date = Date()) -> TypeAheadStep {
        if now.timeIntervalSince(lastKeystroke) > typeAheadTimeout {
            query = ""
        }
        lastKeystroke = now

        if query == String(character) { return .nextMatch(query) }
        query.append(character)
        return .search(query)
    }

    mutating func reset() {
        query = ""
        lastKeystroke = .distantPast
    }
}
