import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// `@`-triggered file-mention overlay: a fuzzy `FileMatch` list from
/// `WorkspaceFileIndex.search(query:limit:)`, rendered through the shared
/// `SageOverlayList` shell and presented via `.ainkradFloatingPanel`
/// anchored to the composer. Selecting a row inserts a `@path` reference (see
/// `SageComposerBar.insertMention`). Presentation-only — keyboard
/// navigation is driven by the composer's shared key monitor.
struct MentionOverlayView: View {
    let matches: [FileMatch]
    @Binding var selectedIndex: Int
    let tokens: DesignTokens
    let onSelect: (FileMatch) -> Void

    var body: some View {
        SageOverlayList(
            isEmpty: matches.isEmpty,
            emptyIcon: "doc.text.magnifyingglass",
            emptyText: "No matching files",
            tokens: tokens
        ) {
            ForEach(Array(matches.enumerated()), id: \.element.path) { index, match in
                AinkradListRow(
                    isSelected: index == selectedIndex,
                    onTap: { onSelect(match) },
                    leading: {
                        Image(systemName: FileGlyph.symbol(forPath: match.path))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tokens.accentSecondary)
                    },
                    title: match.name,
                    subtitle: match.path,
                    trailing: { EmptyView() }
                )
            }
        }
    }
}
