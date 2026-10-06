import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// `/`-triggered slash-command palette: the fuzzy-filtered `CommandRegistry.all()`
/// list, GROUPED into ordered category sections, rendered through the shared
/// `SageOverlayList` shell and presented via `.ainkradFloatingPanel`
/// anchored to the composer. Section headers are non-selectable decoration; the
/// single `selectedIndex` maps across the flattened `selectionOrder` — the same
/// order the composer's key monitor navigates. Presentation-only.
struct CommandPaletteView: View {
    let commands: [SlashCommand]
    let query: String
    @Binding var selectedIndex: Int
    @Environment(\.ainkradTheme) private var theme
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        let sections = CommandPaletteView.grouped(CommandPaletteView.filter(commands, query: query))
        SageOverlayList(
            isEmpty: sections.isEmpty,
            emptyIcon: "magnifyingglass",
            emptyText: "No matching commands"
        ) {
            ForEach(Array(sections.enumerated()), id: \.element.category) { sectionIndex, section in
                // Flat index base = total commands in all earlier sections, so
                // the single `selectedIndex` maps across sections in the SAME
                // flattened order as `selectionOrder`.
                let base = sections[..<sectionIndex].reduce(0) { $0 + $1.commands.count }
                sectionHeader(section.category)
                ForEach(Array(section.commands.enumerated()), id: \.element.name) { offset, command in
                    let flatIndex = base + offset
                    AinkradListRow(
                        isSelected: flatIndex == selectedIndex,
                        onTap: { onSelect(command) },
                        leading: {
                            Image(systemName: "chevron.right.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.accentSecondary)
                        },
                        title: "/\(command.name)",
                        subtitle: command.usage,
                        trailing: { EmptyView() }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ category: CommandCategory) -> some View {
        Text(category.title.uppercased())
            .font(AinkradFont.display(10, weight: .medium))
            .kerning(0.6)
            .foregroundStyle(theme.foreground.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    /// Substring match over the command name and summary — permissive, case-
    /// insensitive. Pure — unit-testable without SwiftUI.
    static func filter(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
    }

    /// Partitions a command list into ordered, non-empty sections by category.
    /// Section order follows `CommandCategory.order`; order WITHIN a section is
    /// the input order (registry order after filtering). Pure.
    static func grouped(_ commands: [SlashCommand]) -> [(category: CommandCategory, commands: [SlashCommand])] {
        CommandCategory.allCases
            .sorted { $0.order < $1.order }
            .compactMap { category in
                let members = commands.filter { $0.category == category }
                return members.isEmpty ? nil : (category, members)
            }
    }

    /// The canonical flattened order the palette both RENDERS and NAVIGATES —
    /// filtered, then grouped, then flattened. The composer's key-driven
    /// selection and this view's rows must use this order so the single
    /// `selectedIndex` maps to the highlighted row. Pure.
    static func selectionOrder(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        grouped(filter(commands, query: query)).flatMap { $0.commands }
    }
}
