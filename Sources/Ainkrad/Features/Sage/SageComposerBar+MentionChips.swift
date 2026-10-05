import AinkradAppKit
import SwiftUI

/// Chip row for committed `@file` mentions (sibling of `attachmentChips`).
/// Each chip shows the file glyph + basename · mode, taps to flip
/// embed⇄reference, and a remove ✕ — all Cardinal HUD, no native chrome.
extension SageComposerBar {
    var mentionChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(mentions.enumerated()), id: \.element.path) { index, mention in
                AinkradChip(
                    label:
                        "\((mention.path as NSString).lastPathComponent) · \(mention.mode == .embed ? "embed" : "ref")",
                    systemName: FileGlyph.symbol(forPath: mention.path),
                    onRemove: { mentions.remove(at: index) }
                )
                .onTapGesture { mentions = SageComposerBar.toggledMode(mentions, at: index) }
            }
            Spacer(minLength: 0)
        }
    }
}
