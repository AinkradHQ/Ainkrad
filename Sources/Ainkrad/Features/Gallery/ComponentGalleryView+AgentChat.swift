#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Agent chat: the pieces Sage and Grimoire build a conversation from.
extension ComponentGalleryView {
    var agentChatSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Agent chat", subtitle: "Streamed markdown, diff review, decisions, composer")

            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradCaption("Markdown Text (headings, inline markup, lists, fenced code)")
                AinkradMarkdownText(text: Self.agentChatMarkdown)
            }

            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradCaption("Diff Review (Split toggles side-by-side; each hunk accepts or rejects)")
                AinkradDiffReview(fileDiff: Self.agentChatDiff, rejectedHunkIDs: $agentChatRejectedHunks)
            }

            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradCaption("Decision Bar")
                AinkradDecisionBar(
                    icon: "terminal", iconTint: .primary, caption: "Approval required",
                    title: "Run swift test in AinkradKit",
                    actions: [
                        .init(title: "Deny", style: .ghost) {},
                        .init(title: "Allow always", style: .secondary) {},
                        .init(title: "Approve", style: .primary) {},
                    ])
            }

            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradCaption("Composer (type / for commands, @ for files)")
                AinkradComposer(
                    text: $agentChatDraft, placeholder: "Message the agent…", isEditable: true,
                    canSend: !agentChatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    autoFocus: false, suggestions: Self.agentChatSuggestions(for:), onPick: { _, _ in },
                    onDrop: nil, onSend: { agentChatDraft = "" }
                ) {
                    AinkradChip(label: "screenshot.png", systemName: "photo") {}
                } leading: {
                    AinkradIconButton(
                        systemName: "hand.raised", size: AinkradComposer<EmptyView, EmptyView, EmptyView>.controlHeight,
                        tooltip: "Permission: Ask"
                    ) {}
                } trailing: {
                    AinkradIconButton(
                        systemName: "ellipsis", size: AinkradComposer<EmptyView, EmptyView, EmptyView>.controlHeight,
                        tooltip: "More"
                    ) {}
                }
            }
        }
    }

    private static let agentChatMarkdown = """
        ## Plan
        Rename the **parser** and keep `MarkdownBlocks.parse` as the single source of truth.

        - Move the files into the kit
        - Point Sage at the kit types

        ```swift
        let blocks = AinkradMarkdownBlocks.parse(text)
        ```
        """

    private static let agentChatDiff = AinkradDiffEngine.compute(
        old: "let a = 1\nlet b = 2\nprint(a + b)\n", new: "let a = 1\nlet b = 3\nprint(a * b)\n",
        path: "Sources/Main.swift")

    private static func agentChatSuggestions(for trigger: AinkradComposerTrigger) -> [AinkradComposerSuggestion] {
        switch trigger {
        case .command(let query):
            return [("review", "Review the current diff"), ("plan", "Plan before editing"), ("clear", "Start fresh")]
                .filter { query.isEmpty || $0.0.contains(query.lowercased()) }
                .map {
                    AinkradComposerSuggestion(
                        id: $0.0, icon: "chevron.right.circle", title: "/\($0.0)", subtitle: $0.1, section: "Session",
                        insertText: "/\($0.0)")
                }
        case .mention(let query):
            return ["Sources/Main.swift", "Package.swift", "README.md"]
                .filter { query.isEmpty || $0.lowercased().contains(query.lowercased()) }
                .map {
                    AinkradComposerSuggestion(
                        id: $0, icon: "doc.text", title: ($0 as NSString).lastPathComponent, subtitle: $0,
                        insertText: "@\($0)")
                }
        @unknown default:
            return []
        }
    }
}
#endif
