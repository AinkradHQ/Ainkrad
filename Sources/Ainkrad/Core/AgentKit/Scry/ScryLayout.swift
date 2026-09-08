import CoreGraphics
import Foundation

/// Places Scry cards. A pure function of (elements, container size, user
/// overrides) — no stored geometry, so nothing can go stale, and the whole
/// thing is testable without a view.
///
/// Shelf packer: walk newest-first, fill a row while spans fit, then start a
/// new row whose height is that of its tallest card. Overridden ids are
/// skipped — they float where the user dropped them (see `ScryView`), and the
/// flow re-packs around the gap.
enum ScryLayout {
    static let padding: CGFloat = 16
    static let gutter: CGFloat = 12
    static let targetColumnWidth: CGFloat = 360

    static func columnCount(for width: CGFloat) -> Int {
        let usable = width - 2 * padding + gutter
        guard usable > 0 else { return 1 }
        return max(1, Int(usable / (targetColumnWidth + gutter)))
    }

    /// Columns a hint occupies, clamped to the available column count.
    static func span(_ hint: ScrySizeHint, columns: Int) -> Int {
        switch hint {
        case .small:  return 1
        case .medium: return 1
        case .large:  return min(2, columns)
        case .full:   return columns
        }
    }

    static func height(_ hint: ScrySizeHint) -> CGFloat {
        switch hint {
        case .small:  return 72
        case .medium: return 240
        case .large:  return 320
        case .full:   return 280
        }
    }

    static func frames(for elements: [ScryElement],
                       in size: CGSize,
                       overrides: [String: ScryRect]) -> [String: ScryRect] {
        let columns = columnCount(for: size.width)
        let usableWidth = max(0, size.width - 2 * padding)
        let columnWidth = (usableWidth - gutter * CGFloat(columns - 1)) / CGFloat(columns)

        var result: [String: ScryRect] = [:]
        var cursorColumn = 0
        var rowTop = padding
        var rowHeight: CGFloat = 0

        // Newest first: `elements` is append-ordered, so reverse it.
        for element in elements.reversed() where overrides[element.id] == nil {
            let cardSpan = span(element.sizeHint, columns: columns)
            if cursorColumn > 0 && cursorColumn + cardSpan > columns {
                rowTop += rowHeight + gutter
                rowHeight = 0
                cursorColumn = 0
            }
            let width = columnWidth * CGFloat(cardSpan) + gutter * CGFloat(cardSpan - 1)
            let cardHeight = height(element.sizeHint)
            result[element.id] = ScryRect(
                x: Double(padding + CGFloat(cursorColumn) * (columnWidth + gutter)),
                y: Double(rowTop),
                width: Double(width),
                height: Double(cardHeight))
            rowHeight = max(rowHeight, cardHeight)
            cursorColumn += cardSpan
            if cursorColumn >= columns {
                rowTop += rowHeight + gutter
                rowHeight = 0
                cursorColumn = 0
            }
        }
        return result
    }

    /// Total height the flow occupies — the scroll content height.
    static func contentHeight(for elements: [ScryElement],
                              in size: CGSize,
                              overrides: [String: ScryRect]) -> CGFloat {
        let frames = frames(for: elements, in: size, overrides: overrides)
        // Must also span overridden (floating) cards: `frames` excludes them
        // by design, so a card dragged below the flow's bottom would
        // otherwise shrink the scrollable content and strand itself outside
        // the reachable region.
        let flowBottom = frames.values.map { CGFloat($0.y + $0.height) }.max() ?? 0
        let overrideBottom = overrides.values.map { CGFloat($0.y + $0.height) }.max() ?? 0
        return max(flowBottom, overrideBottom) + padding
    }
}
