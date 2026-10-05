// Tests/AinkradTests/SubagentRegistryFilterTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SubagentRegistryFilter")
@MainActor
struct SubagentRegistryFilterTests {
    private var allTools: [any AgentTool] {
        [ReadFileTool(), EditFileTool()]  // read + write host tools
    }

    @Test func emptyAllowKeepsEverything() {
        let filtered = SubagentRegistryFilter.tools(from: allTools, allow: [], policy: nil)
        #expect(Set(filtered.map(\.name)) == ["read_file", "edit_file"])
    }

    @Test func allowListNarrows() {
        let filtered = SubagentRegistryFilter.tools(from: allTools, allow: ["read_file"], policy: nil)
        #expect(filtered.map(\.name) == ["read_file"])
    }

    @Test func allowListWithUnknownNameFabricatesNothing() {
        // "no_such_tool" isn't in the source registry — must NOT appear in the output,
        // and must not cause a crash. Only "read_file" survives.
        let filtered = SubagentRegistryFilter.tools(
            from: allTools,
            allow: ["read_file", "no_such_tool"],
            policy: nil)
        #expect(filtered.map(\.name) == ["read_file"])
    }

    @Test func policyFurtherNarrowsToReadOnly() {
        let policy = AgentToolPolicy.restricted(allow: [], deny: [], allowClasses: [.read])
        let filtered = SubagentRegistryFilter.tools(from: allTools, allow: [], policy: policy)
        #expect(filtered.map(\.name) == ["read_file"])  // edit_file (.write) dropped
    }

    @Test func denyOverridesAllow() {
        // Policy explicitly denies edit_file even though the allow-list names it —
        // deny must win over allow per AgentToolPolicy.allows semantics.
        let policy = AgentToolPolicy.restricted(
            allow: ["edit_file"], deny: ["edit_file"],
            allowClasses: [])
        let filtered = SubagentRegistryFilter.tools(
            from: allTools, allow: ["edit_file"],
            policy: policy)
        #expect(filtered.isEmpty)
    }

    @Test func orderIsPreserved() {
        let filtered = SubagentRegistryFilter.tools(
            from: allTools,
            allow: ["edit_file", "read_file"],
            policy: nil)
        // Source order (ReadFileTool, EditFileTool) is preserved, not allow-list order.
        #expect(filtered.map(\.name) == ["read_file", "edit_file"])
    }

    @Test func outputIsAlwaysSubsetOfInput() {
        // The narrows-only invariant: no combination of allow/policy can introduce a
        // tool name absent from the source array.
        let policy = AgentToolPolicy.restricted(
            allow: ["read_file", "edit_file", "ghost_tool"],
            deny: [], allowClasses: [.read, .write, .memory])
        let filtered = SubagentRegistryFilter.tools(
            from: allTools,
            allow: ["read_file", "edit_file", "ghost_tool"],
            policy: policy)
        let sourceNames = Set(allTools.map(\.name))
        #expect(Set(filtered.map(\.name)).isSubset(of: sourceNames))
    }
}
