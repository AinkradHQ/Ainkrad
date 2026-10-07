import Testing

@testable import AinkradHostRuntime

@Suite("AppIDRenames")
struct AppIDRenamesTests {
    @Test("maps every retired id to its replacement")
    func mapIsComplete() {
        #expect(
            AppIDRenames.map == [
                "files": "hoard", "assistant": "sage", "canvas": "scry", "terminal": "rune",
            ])
    }

    @Test("re-keys a JSON object, leaving unrelated keys alone")
    func rekeysObject() {
        let before: [String: JSONValue] = [
            "files": .bool(true), "gitmage": .bool(false),
        ]
        #expect(
            AppIDRenames.rekeyed(before) == [
                "hoard": .bool(true), "gitmage": .bool(false),
            ])
    }

    @Test("an existing new-id key wins over a migrated old-id key")
    func newKeyWins() {
        let before: [String: JSONValue] = ["files": .bool(true), "hoard": .bool(false)]
        #expect(AppIDRenames.rekeyed(before) == ["hoard": .bool(false)])
    }

    @Test("rewrites a tool-name prefix")
    func rewritesToolPrefix() {
        #expect(AppIDRenames.renamedToolName("files_navigate") == "hoard_navigate")
        #expect(AppIDRenames.renamedToolName("files_*") == "hoard_*")
    }

    @Test("the canvas render tool is covered by the shared prefix rule")
    func coversCanvasRender() {
        #expect(AppIDRenames.renamedToolName("canvas_render") == "scry_render")
    }

    @Test("leaves a tool whose name merely CONTAINS a retired id alone")
    func leavesUnrelatedToolsAlone() {
        // The host's own shell tool. Renaming it would break every existing
        // permission allowlist entry and hook for no reason.
        #expect(AppIDRenames.renamedToolName("run_terminal") == "run_terminal")
        #expect(AppIDRenames.renamedToolName("*") == "*")
    }
}
