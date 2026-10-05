import AinkradHostRuntime
// Tests/AinkradTests/MCPArgumentRiskTests.swift
import Testing

@testable import Ainkrad

@Suite("MCPArgumentRisk")
struct MCPArgumentRiskTests {
    @Test("a plain payload carries no option-looking value")
    func plainPayloadIsClean() {
        #expect(
            !MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "repoPath": .string("/tmp/repo"), "message": .string("fix: thing"),
                ])))
    }

    @Test("a leading-dash value anywhere is flagged")
    func leadingDashIsFlagged() {
        #expect(
            MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "branch": .string("--upload-pack=/bin/sh")
                ])))
    }

    @Test("recurses into nested arrays and objects")
    func recursesIntoNestedValues() {
        #expect(
            MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "args": .object(["paths": .array([.string("ok"), .string("--exec=sh")])])
                ])))
    }

    @Test("the ext:: transport helper is flagged even without a dash")
    func extTransportIsFlagged() {
        #expect(
            MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "url": .string("ext::sh -c whoami")
                ])))
    }

    // The rule only ever inspects `.string` values for option-looking
    // forms — a `.number` can never match `hasPrefix`/`ext::`. So this
    // doesn't prove some special negative-number carve-out; it proves the
    // walk doesn't misfire on non-string JSON at all.
    @Test("a bare negative number is not an option")
    func negativeNumberIsNotAnOption() {
        #expect(!MCPArgumentRisk.hasOptionLookingValue(.object(["count": .number(-5)])))
    }

    @Test("a single top-level leading-dash string is flagged")
    func topLevelLeadingDashIsFlagged() {
        #expect(MCPArgumentRisk.hasOptionLookingValue(.string("-c")))
    }

    @Test("ext:: is case-insensitively flagged")
    func extTransportIsCaseInsensitive() {
        #expect(
            MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "url": .string("EXT::sh -c whoami")
                ])))
    }

    // MARK: - prose must not flag
    //
    // The discriminator these encode: a CLI option's dash is immediately
    // followed by an alphanumeric; markdown's is followed by a space or by
    // more dashes. Content-bearing tools (Lore's create_note/save_note) carry
    // markdown bodies, and flagging every leading dash meant an approval
    // prompt on the majority of benign note writes. If someone loosens this
    // back to `hasPrefix("-")`, these are the tests that will say why not.

    @Test("a markdown bullet is not an option")
    func markdownBulletIsNotFlagged() {
        #expect(!MCPArgumentRisk.hasOptionLookingValue(.object(["body": .string("- item")])))
    }

    @Test("a markdown horizontal rule / frontmatter fence is not an option")
    func horizontalRuleIsNotFlagged() {
        #expect(!MCPArgumentRisk.hasOptionLookingValue(.object(["body": .string("---")])))
    }

    @Test("a bare double dash is not an option")
    func bareDoubleDashIsNotFlagged() {
        #expect(!MCPArgumentRisk.hasOptionLookingValue(.object(["body": .string("-- ")])))
    }

    @Test("a multi-line markdown body with bullets is not an option")
    func markdownBodyIsNotFlagged() {
        #expect(
            !MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "title": .string("Notes"),
                    "body": .string("---\ntags: [x]\n---\n\n# Heading\n\n- first\n- second\n"),
                ])))
    }

    @Test("an ordinary sentence is not an option")
    func plainSentenceIsNotFlagged() {
        #expect(
            !MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "query": .string("what did I write about caching")
                ])))
    }

    // MARK: - the real attack forms, all of which still flag
    //
    // Inherited from the deleted `GitOpTool.optionLookingValue`, whose docs
    // cited exactly these. Git Mage's MCP tools now rely on this rule, so a
    // regression here is a regression in git argument-injection defense.

    @Test("every documented git argument-injection form is still flagged")
    func gitInjectionFormsAreStillFlagged() {
        for value in [
            "--upload-pack=/bin/sh", "--receive-pack=/bin/sh", "--exec=sh",
            "-c", "-c core.pager=sh", "-o ProxyCommand=sh", "--output=/tmp/x",
            "-C", "--config=x", "-4",
        ] {
            #expect(
                MCPArgumentRisk.hasOptionLookingValue(.object(["v": .string(value)])),
                "\"\(value)\" stopped being flagged")
        }
    }

    @Test("a short-form leading-dash flag is flagged")
    func shortFormDashIsFlagged() {
        #expect(
            MCPArgumentRisk.hasOptionLookingValue(
                .object([
                    "opt": .string("-c core.pager=sh")
                ])))
    }
}
