import AinkradHostRuntime
// Tests/AinkradTests/CommandRegistryTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("CommandRegistry")
@MainActor
struct CommandRegistryTests {
    @Test func parsesKnownCommand() {
        let reg = CommandRegistry(builtins: [
            SlashCommand(name: "model", summary: "", usage: "/model <id>") { _, _ in .handled(note: nil) }
        ])
        let parsed = reg.parse("/model gpt-5")
        #expect(parsed?.command.name == "model")
        #expect(parsed?.args == "gpt-5")
    }

    @Test func plainTextIsNotACommand() {
        let reg = CommandRegistry(builtins: [])
        if case .notACommand = reg.run("hello there", on: TestSessionFactory.make()) {
        } else {
            Issue.record("expected notACommand")
        }
    }

    @Test func skillCommandsCanBeRegistered() {
        let reg = CommandRegistry(builtins: [])
        reg.register(SlashCommand(name: "deploy", summary: "", usage: "/deploy") { _, _ in .handled(note: "ok") })
        #expect(reg.all().contains { $0.name == "deploy" })
    }

    @Test func unknownSlashCommandSurfacesANote() {
        let reg = CommandRegistry(builtins: [])
        #expect(reg.run("/nope", on: TestSessionFactory.make()) == .handled(note: "Unknown command."))
    }

    @Test func argsAreEmptyWhenNoneGiven() {
        let reg = CommandRegistry(builtins: [
            SlashCommand(name: "usage", summary: "", usage: "/usage") { args, _ in .handled(note: args) }
        ])
        #expect(reg.run("/usage", on: TestSessionFactory.make()) == .handled(note: ""))
    }

    // MARK: - Built-in command behavior (BuiltinCommands.make)

    @Test func rememberBuiltinWritesToMemoryAndIsSilent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore())
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(memory: svc)
        let result = reg.run("/remember call me Ahmed", on: session)
        #expect(result == .handled(note: nil))
        #expect(svc.store.read(.memory).contains("call me Ahmed"))
    }

    @Test func modelBuiltinPinsViaRuntime() {
        let persistence = InMemoryPersistenceStore()
        let runtime = RuntimeOptionsStore(persistence: persistence)
        let reg = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: runtime, usage: nil, router: nil, catalog: nil))
        let result = reg.run("/model gpt-5", on: TestSessionFactory.make())
        #expect(runtime.options.pinnedModel == "gpt-5")
        if case .handled(let note) = result {
            #expect(note?.contains("gpt-5") == true)
        } else {
            Issue.record("expected handled")
        }
    }

    @Test func usageModelAutoClearsPin() {
        let persistence = InMemoryPersistenceStore()
        let runtime = RuntimeOptionsStore(persistence: persistence)
        let reg = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: runtime, usage: nil, router: nil, catalog: nil))

        let pinResult = reg.run("/model gpt-5", on: TestSessionFactory.make())
        #expect(runtime.options.pinnedModel == "gpt-5")
        if case .handled(let note) = pinResult {
            #expect(note?.contains("gpt-5") == true)
        } else {
            Issue.record("expected handled")
        }

        let autoResult = reg.run("/model auto", on: TestSessionFactory.make())
        #expect(runtime.options.pinnedModel == nil)
        if case .handled(let note) = autoResult {
            #expect(note?.contains("Auto") == true)
        } else {
            Issue.record("expected handled")
        }
    }

    @Test func thinkBuiltinRejectsUnknownLevels() {
        let persistence = InMemoryPersistenceStore()
        let runtime = RuntimeOptionsStore(persistence: persistence)
        let reg = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: runtime, usage: nil, router: nil, catalog: nil))
        let result = reg.run("/think ludicrous", on: TestSessionFactory.make())
        #expect(result == .handled(note: "Usage: /think <low|medium|high|max>"))
        #expect(runtime.options.thinkLevel == "medium")  // unchanged
    }

    @Test func thinkBuiltinNoticesWhenModelLacksReasoningEffort() {
        let persistence = InMemoryPersistenceStore()
        let runtime = RuntimeOptionsStore(persistence: persistence)
        let catalog = ModelCatalog()
        let reg = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: runtime, usage: nil, router: nil, catalog: catalog))
        // TestSessionFactory.make() defaults to the "claude" preset/config default
        // model, "claude-opus-4-8", which DOES support reasoningEffort — use a
        // session whose config model is one the catalog marks as NOT supporting it
        // (claude-haiku-4-8, per `ModelCatalog.compiledDefaults`).
        let session = TestSessionFactory.make(configModel: "claude-haiku-4-8")
        let result = reg.run("/think max", on: session)
        #expect(runtime.options.thinkLevel == "max")
        if case .handled(let note) = result {
            #expect(note?.contains("no effect") == true)
        } else {
            Issue.record("expected handled")
        }
    }

    @Test func verboseAndTraceBuiltinsToggleRuntime() {
        let persistence = InMemoryPersistenceStore()
        let runtime = RuntimeOptionsStore(persistence: persistence)
        let reg = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: runtime, usage: nil, router: nil, catalog: nil))
        _ = reg.run("/verbose on", on: TestSessionFactory.make())
        #expect(runtime.options.verbose)
        _ = reg.run("/trace on", on: TestSessionFactory.make())
        #expect(runtime.options.trace)
        _ = reg.run("/verbose off", on: TestSessionFactory.make())
        #expect(!runtime.options.verbose)
    }

    @Test func newAndResetBuiltinsClearSessionAndPin() {
        let persistence = InMemoryPersistenceStore()
        let runtime = RuntimeOptionsStore(persistence: persistence)
        runtime.pinModel("gpt-5")
        let reg = CommandRegistry(
            builtins: BuiltinCommands.make(runtime: runtime, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make()
        _ = reg.run("/new", on: session)
        #expect(session.messages.isEmpty)
        #expect(runtime.options.pinnedModel == nil)
    }

    // Regression: an UNPRICED session (no `ModelPriceTable` entry for the
    // model, so cost stays 0 — "never priced", not a real zero-dollar turn)
    // must show "cost unknown", never a fabricated "$0.0000"/"$0.00". Mirrors
    // `formattedUsageCost`'s `cost > 0` convention in `UsageDashboardView.swift`
    // so the two surfaces agree. Fails against the old unconditional-format code.
    @Test func usageBuiltinShowsCostUnknownForUnpricedSession() {
        let usage = UsageTracker(persistence: InMemoryPersistenceStore(), prices: ModelPriceTable())
        usage.record(model: "unknown-xyz", usage: TokenUsage(input: 500, output: 500), baselineModel: nil)
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: usage, router: nil, catalog: nil))
        let result = reg.run("/usage", on: TestSessionFactory.make())
        guard case .handled(let note) = result, let note else {
            Issue.record("expected handled note")
            return
        }
        #expect(note.contains("cost unknown"))
        #expect(!note.contains("$0.0000"))
        #expect(!note.contains("$0.00 "))
    }

    @Test func usageBuiltinShowsRealDollarFigureForPricedSession() {
        let usage = UsageTracker(persistence: InMemoryPersistenceStore(), prices: ModelPriceTable())
        usage.record(model: "gpt-5-mini", usage: TokenUsage(input: 1_000_000, output: 1_000_000), baselineModel: nil)
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: usage, router: nil, catalog: nil))
        let result = reg.run("/usage", on: TestSessionFactory.make())
        guard case .handled(let note) = result, let note else {
            Issue.record("expected handled note")
            return
        }
        #expect(note.contains("$"))
        #expect(!note.contains("cost unknown"))
    }
}
