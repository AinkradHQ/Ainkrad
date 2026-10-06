import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// Name entry for rename and new folder, plus the "only one pane open"
/// explanation. One file because they are the same shape — a short modal with
/// a field or a message — and splitting them would be three near-identical
/// files.
struct HoardPromptSheet: View {
    let prompt: HoardPrompt
    let onCancel: () -> Void
    let onRename: (FileEntry, String) -> Void
    let onNewFolder: (String) -> Void

    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            Text(title)
                .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                .foregroundStyle(theme.foreground)

            switch prompt {
            case .rename, .newFolder:
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(AinkradFontResolver.font(.body, typography: typo))
                    .focused($fieldFocused)
                    .padding(.horizontal, AinkradSpacing.sm)
                    .padding(.vertical, 6)
                    .background(ChamferShape(cut: 4).fill(theme.foreground.opacity(0.08)))
                    .onSubmit(commit)

            case .noDestination(let isMove):
                Text(
                    """
                    Open a second Hoard pane to \(isMove ? "move" : "copy") into. \
                    Hoard uses the workspace's own tiling for its second pane rather \
                    than splitting inside one.
                    """
                )
                .font(AinkradFontResolver.font(.body, typography: typo))
                .foregroundStyle(theme.foreground.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AinkradSpacing.sm) {
                Spacer()
                AinkradButton(title: cancelTitle, style: .ghost, action: onCancel)
                if let confirmTitle {
                    AinkradButton(title: confirmTitle, style: .primary, action: commit)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(AinkradSpacing.xl)
        .frame(width: 420)
        .hudPanelChrome(tokens: environment.themeManager.tokens)
        .onAppear {
            if case .rename(let entry) = prompt { text = entry.name }
            fieldFocused = true
        }
    }

    private var title: String {
        switch prompt {
        case .rename: return "Rename"
        case .newFolder: return "New Folder"
        case .noDestination(let isMove): return isMove ? "Nowhere to Move To" : "Nowhere to Copy To"
        }
    }

    private var placeholder: String {
        if case .newFolder = prompt { return "untitled folder" }
        return "Name"
    }

    private var cancelTitle: String {
        if case .noDestination = prompt { return "OK" }
        return "Cancel"
    }

    private var confirmTitle: String? {
        switch prompt {
        case .rename: return "Rename"
        case .newFolder: return "Create"
        case .noDestination: return nil
        }
    }

    private func commit() {
        switch prompt {
        case .rename(let entry): onRename(entry, text)
        case .newFolder: onNewFolder(text)
        case .noDestination: onCancel()
        }
    }
}

/// Replace / Keep both / Skip / Merge, with apply-to-all.
///
/// Wears the host's `hudPanelChrome` and the kit's own controls. The first cut
/// used a stock SwiftUI `Toggle` on a plain rounded background, which read as a
/// system alert dropped into Ainkrad rather than part of it.
struct ConflictSheet: View {
    let question: ConflictQuestion
    let onAnswer: (ConflictAnswer) -> Void

    @State private var applyToAll = false

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors

    private var tokens: DesignTokens { environment.themeManager.tokens }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
            header
            // One decision for the whole batch — the reason a 200-file
            // conflict isn't 200 dialogs.
            AinkradCheckbox(isOn: $applyToAll, label: "Apply to all remaining")
            actions
        }
        .padding(AinkradSpacing.xl)
        .frame(width: 520)
        .hudPanelChrome(tokens: tokens)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColors.warning)
                .frame(width: 26, height: 26)
                .background(ChamferShape(cut: 5).fill(statusColors.warning.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text("\u{201C}\(question.name)\u{201D} already exists")
                    .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(question.destination.deletingLastPathComponent().path)
                    .font(AinkradFontResolver.font(.caption, typography: typo))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: AinkradSpacing.sm) {
            // Skip is the safe default and sits furthest from Replace, which
            // is the one that destroys something.
            AinkradButton(title: "Skip", style: .ghost) { answer(.skip) }
            Spacer()
            AinkradButton(title: "Keep Both", style: .secondary) { answer(.keepBoth) }
            if question.isDirectory {
                AinkradButton(title: "Merge", style: .secondary) { answer(.merge) }
            }
            // Danger, not primary: replacing sends the existing file to the
            // Trash, and the button should say so by colour.
            AinkradButton(title: "Replace", style: .danger) { answer(.replace) }
        }
    }

    private func answer(_ policy: ConflictPolicy) {
        onAnswer(ConflictAnswer(policy: policy, applyToAll: applyToAll))
    }
}
