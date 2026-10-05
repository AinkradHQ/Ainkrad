import Foundation

/// Search has three states. The palette answers "where is it?"; filtering is
/// what you get once you have gone somewhere with the query still live, and
/// it dims rather than hides so the page keeps its shape.
enum SettingsSearchMode: Equatable {
    case browsing
    case palette(String)
    case filtering(String)

    init(query: String, hasNavigated: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self = .browsing
        } else if hasNavigated {
            self = .filtering(trimmed)
        } else {
            self = .palette(trimmed)
        }
    }

    var query: String? {
        switch self {
        case .browsing: return nil
        case .palette(let q), .filtering(let q): return q
        }
    }

    /// A sidebar row tap is an unambiguous "take me to this page" instruction
    /// — it must always produce a visible result, so it always behaves as a
    /// navigation (`hasNavigated: true`), regardless of which mode it was
    /// tapped from. From `.browsing` that's a no-op (still `.browsing`); from
    /// `.palette` it must replace the palette with the tapped page rather
    /// than silently leaving the palette on screen (the defect this fixes);
    /// from `.filtering` it stays `.filtering` on the newly tapped page. The
    /// two live-query modes therefore always agree after a tap.
    func afterSidebarTap() -> SettingsSearchMode {
        SettingsSearchMode(query: query ?? "", hasNavigated: true)
    }
}
