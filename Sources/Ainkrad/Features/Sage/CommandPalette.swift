import Foundation

/// The `/` palette's ordering: the fuzzy-filtered `CommandRegistry.all()` list,
/// GROUPED into ordered category sections. The kit composer renders the rows
/// (`AinkradComposer`); this decides which rows and in what order. Pure.
enum CommandPalette {
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
