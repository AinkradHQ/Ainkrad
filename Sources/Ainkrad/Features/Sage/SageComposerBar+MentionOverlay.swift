import AinkradAppKit
import SwiftUI

/// Command palette / `@`-mention overlay logic for `SageComposerBar`
/// (M7 finalize Wave D, D2 — extracted verbatim, no behavior change).
extension SageComposerBar {
    var filteredCommands: [SlashCommand] {
        CommandPaletteView.selectionOrder(environment.commandRegistry.all(), query: paletteQuery)
    }

    var mentionMatches: [FileMatch] {
        environment.workspaceFileIndex.search(mentionQuery, limit: 8)
    }

    /// Recomputes trigger state from the live draft. The palette wins when
    /// both could apply (it can't in practice — the palette only fires on a
    /// LEADING `/`, the mention overlay on a trailing `@` token — but the
    /// precedence keeps this deterministic if that ever changes).
    func updateOverlayTriggers(_ text: String) {
        if let q = ComposerTriggers.paletteQuery(in: text) {
            if !isPaletteVisible { paletteSelectedIndex = 0 }
            paletteQuery = q
            isPaletteVisible = true
            isMentionVisible = false
            return
        }
        isPaletteVisible = false

        if let q = ComposerTriggers.mentionQuery(in: text) {
            if !isMentionVisible { mentionSelectedIndex = 0 }
            mentionQuery = q
            isMentionVisible = true
        } else {
            isMentionVisible = false
        }
    }

    func moveSelection(by delta: Int) {
        if isPaletteVisible {
            let count = filteredCommands.count
            guard count > 0 else { return }
            paletteSelectedIndex = (paletteSelectedIndex + delta + count) % count
        } else if isMentionVisible {
            let count = mentionMatches.count
            guard count > 0 else { return }
            mentionSelectedIndex = (mentionSelectedIndex + delta + count) % count
        }
    }

    func confirmSelection() {
        if isPaletteVisible {
            let rows = filteredCommands
            guard rows.indices.contains(paletteSelectedIndex) else { return }
            insertCommand(rows[paletteSelectedIndex])
        } else if isMentionVisible {
            let rows = mentionMatches
            guard rows.indices.contains(mentionSelectedIndex) else { return }
            insertMention(rows[mentionSelectedIndex])
        }
    }

    /// Replaces the leading `/command` token being typed with `/name ` —
    /// the user keeps typing args (or presses Return/send to run it as-is,
    /// same as typing the whole command by hand).
    func insertCommand(_ command: SlashCommand) {
        draft = "/\(command.name) "
        isPaletteVisible = false
    }

    /// Replaces the trailing `@query` token being typed with `@path ` —
    /// see `ComposerTriggers.trailingToken` for why "trailing" is the token
    /// this overlay always acts on (no cursor position is available).
    func insertMention(_ match: FileMatch) {
        if let idx = draft.lastIndex(where: { $0.isWhitespace }) {
            let tokenStart = draft.index(after: idx)
            draft.replaceSubrange(tokenStart..., with: "@\(match.path) ")
        } else {
            draft = "@\(match.path) "
        }
        if !mentions.contains(where: { $0.path == match.path }) {
            mentions.append(ComposerMention(path: match.path))
        }
        isMentionVisible = false
    }
}
