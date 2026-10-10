import AinkradAppKit
import SwiftUI

/// The composer's `/` and `@` overlay rows: slash commands from the registry,
/// files from the workspace index. The kit composer owns the overlay itself.
extension SageComposerBar {
    func suggestions(for trigger: AinkradComposerTrigger) -> [AinkradComposerSuggestion] {
        switch trigger {
        case .command(let query):
            return CommandPalette.selectionOrder(environment.commandRegistry.all(), query: query).map { command in
                AinkradComposerSuggestion(
                    id: command.name, icon: "chevron.right.circle", title: "/\(command.name)",
                    subtitle: command.usage, section: command.category.title, insertText: "/\(command.name)")
            }
        case .mention(let query):
            return environment.workspaceFileIndex.search(query, limit: 8).map { match in
                AinkradComposerSuggestion(
                    id: match.path, icon: FileGlyph.symbol(forPath: match.path), title: match.name,
                    subtitle: match.path, insertText: "@\(match.path)")
            }
        @unknown default:
            return []
        }
    }

    /// A picked file becomes a committed mention, carried into the next send.
    func picked(_ trigger: AinkradComposerTrigger, _ suggestion: AinkradComposerSuggestion) {
        guard case .mention = trigger, !mentions.contains(where: { $0.path == suggestion.id }) else { return }
        mentions.append(ComposerMention(path: suggestion.id))
    }
}
