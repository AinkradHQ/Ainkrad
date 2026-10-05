import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// Rename many files at once, with the result visible before anything happens.
///
/// The preview is the whole point. Batch rename is the highest-blast-radius
/// operation in the app and its failure mode is renaming 400 files
/// correctly-but-wrongly — a plan you can read beats an undo scramble. Rows
/// that cannot be applied stay in the list, greyed and labelled, rather than
/// disappearing: a vanished row reads as "nothing matched", which is a
/// different problem with a different fix.
struct BatchRenameSheet: View {
    let entries: [FileEntry]
    /// Names already in the folder — the collision check's other half.
    let siblings: Set<String>
    let onCancel: () -> Void
    let onApply: ([BatchRenamePlanItem]) -> Void

    @State private var mode: BatchRenameMode = .findReplace
    @State private var find = ""
    @State private var replace = ""
    @State private var startNumber = 1
    @FocusState private var fieldFocused: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors

    private var tokens: DesignTokens { environment.themeManager.tokens }

    private var plan: [BatchRenamePlanItem] {
        batchRenamePlan(
            entries: entries, mode: mode, find: find, replace: replace,
            existingNames: siblings, startNumber: startNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
            header
            controls
            preview
            footer
        }
        .padding(AinkradSpacing.xl)
        .frame(width: 640)
        .hudPanelChrome(tokens: tokens)
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.md) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.accentSecondary)
                .frame(width: 26, height: 26)
                .background(ChamferShape(cut: 5).fill(tokens.accentSecondary.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Rename \(entries.count) Item\(entries.count == 1 ? "" : "s")")
                    .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                Text(entries.first?.url.deletingLastPathComponent().path ?? "")
                    .font(AinkradFontResolver.font(.caption, typography: typo))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSegmentedPicker(items: BatchRenameMode.allCases, selection: $mode) {
                $0.title
            }

            HStack(spacing: AinkradSpacing.sm) {
                if mode == .findReplace {
                    AinkradTextField(text: $find, placeholder: "Find")
                        .focused($fieldFocused)
                    AinkradTextField(text: $replace, placeholder: "Replace with")
                } else if mode == .numberSequentially {
                    AinkradTextField(text: $replace, placeholder: "Base name (blank keeps each name)")
                        .focused($fieldFocused)
                    // Sequences that start at 1 are the common case, but a
                    // second batch appended to an existing set needs to start
                    // where the last one stopped.
                    AinkradStepper(value: $startNumber, in: 0...9999)
                } else {
                    AinkradTextField(
                        text: $replace,
                        placeholder: mode == .addPrefix ? "Prefix" : "Suffix"
                    )
                    .focused($fieldFocused)
                }
            }
        }
    }

    private var preview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(plan) { item in
                    row(item)
                }
            }
        }
        .frame(height: 220)
        .background(ChamferShape(cut: 6).fill(tokens.foreground.opacity(0.05)))
    }

    private func row(_ item: BatchRenamePlanItem) -> some View {
        HStack(spacing: AinkradSpacing.sm) {
            Text(item.entry.name)
                .foregroundStyle(tokens.foreground.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(tokens.foreground.opacity(0.3))

            Text(item.problem == nil ? item.newName : (item.problem.map(label) ?? ""))
                .foregroundStyle(
                    item.problem == nil
                        ? tokens.foreground
                        : (item.problem == .unchanged
                            ? tokens.foreground.opacity(0.35)
                            : statusColors.warning)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AinkradFontResolver.font(.caption, typography: typo))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, 4)
    }

    private func label(_ problem: BatchRenamePlanItem.Problem) -> String {
        switch problem {
        case .unchanged: return "unchanged"
        case .emptyResult: return "would leave no name"
        case .collidesWithExisting: return "a file with that name already exists"
        case .collidesWithAnotherRename: return "two files would get the same name"
        }
    }

    private var footer: some View {
        let summary = plan.renameSummary
        return HStack(spacing: AinkradSpacing.sm) {
            Text(summaryText(summary))
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(
                    summary.blocked > 0
                        ? statusColors.warning
                        : tokens.foreground.opacity(0.55))
            Spacer()
            AinkradButton(title: "Cancel", style: .ghost, action: onCancel)
            AinkradButton(title: "Rename", style: .primary) { onApply(plan) }
                .disabled(!summary.canApply)
        }
    }

    private func summaryText(_ summary: BatchRenameSummary) -> String {
        guard summary.willRename > 0 || summary.blocked > 0 else {
            return "No names would change"
        }
        var parts = ["\(summary.willRename) will be renamed"]
        // Skipped rows are stated, never silent — a batch that quietly does
        // less than it looks like it does is worse than one that refuses.
        if summary.blocked > 0 { parts.append("\(summary.blocked) blocked and skipped") }
        if summary.unchanged > 0 { parts.append("\(summary.unchanged) unchanged") }
        return parts.joined(separator: " · ")
    }
}

extension BatchRenameMode {
    var title: String {
        switch self {
        case .findReplace: return "Find & Replace"
        case .addPrefix: return "Add Prefix"
        case .addSuffix: return "Add Suffix"
        case .numberSequentially: return "Number"
        }
    }
}
