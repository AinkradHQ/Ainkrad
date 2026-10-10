import Testing

@testable import Ainkrad

@Suite("CommandCategory")
@MainActor
struct CommandCategoryTests {
    @Test func defaultCategoryIsOther() {
        let c = SlashCommand(name: "x", summary: "", usage: "/x") { _, _ in .handled(note: nil) }
        #expect(c.category == .other)
    }

    @Test func titlesAndOrder() {
        #expect(CommandCategory.session.title == "Session")
        #expect(CommandCategory.skill.title == "Skills")
        #expect(CommandCategory.session.order < CommandCategory.model.order)
        #expect(CommandCategory.model.order < CommandCategory.info.order)
        #expect(CommandCategory.info.order < CommandCategory.memory.order)
        #expect(CommandCategory.memory.order < CommandCategory.skill.order)
        #expect(CommandCategory.skill.order < CommandCategory.other.order)
    }

    @Test func builtinsAreCategorized() {
        let cmds = BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil)
        func category(_ name: String) -> CommandCategory? { cmds.first { $0.name == name }?.category }
        #expect(category("new") == .session)
        #expect(category("reset") == .session)
        #expect(category("compact") == .session)
        #expect(category("undo") == .session)
        #expect(category("retry") == .session)
        #expect(category("model") == .model)
        #expect(category("think") == .model)
        #expect(category("usage") == .info)
        #expect(category("export") == .info)
        #expect(category("verbose") == .info)
        #expect(category("trace") == .info)
        #expect(category("remember") == .memory)
    }

    private func namedCmd(_ name: String, _ cat: CommandCategory) -> SlashCommand {
        SlashCommand(name: name, summary: "\(name) does things", usage: "/\(name)", category: cat) { _, _ in
            .handled(note: nil)
        }
    }

    @Test func groupedOrdersSectionsAndOmitsEmpty() {
        let cmds = [namedCmd("remember", .memory), namedCmd("new", .session), namedCmd("model", .model)]
        let sections = CommandPalette.grouped(cmds)
        #expect(sections.map(\.category) == [.session, .model, .memory])
    }

    @Test func groupedPreservesWithinSectionOrder() {
        let cmds = [namedCmd("retry", .session), namedCmd("new", .session)]
        let sections = CommandPalette.grouped(cmds)
        #expect(sections.first?.commands.map(\.name) == ["retry", "new"])
    }

    @Test func selectionOrderIsFlattenedGrouping() {
        let cmds = [namedCmd("remember", .memory), namedCmd("new", .session), namedCmd("usage", .info)]
        #expect(CommandPalette.selectionOrder(cmds, query: "").map(\.name) == ["new", "usage", "remember"])
    }

    @Test func selectionOrderAppliesFilterFirst() {
        let cmds = [namedCmd("remember", .memory), namedCmd("new", .session)]
        #expect(CommandPalette.selectionOrder(cmds, query: "rem").map(\.name) == ["remember"])
    }
}
