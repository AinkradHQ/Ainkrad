import Testing

@testable import Ainkrad

@Suite("RedactionList")
struct RedactionListTests {
    @Test func splitsTrimsAndDropsEmpties() {
        let out = RedactionList.parse(" sk-live-abc , jane@example.com ,, ")
        #expect(out == ["sk-live-abc", "jane@example.com"])
    }

    @Test func emptyInputYieldsEmpty() {
        #expect(RedactionList.parse("   ").isEmpty)
    }

    @Test func applyRemovesSecretsBeforeAnyTruncation() {
        // The share flow redacts THEN truncates: a secret must be gone before the
        // 60-char title cut, or a straddling fragment would leak.
        let raw = "prefix padding padding padding padding pad sk-live-SECRET tail"
        let redacted = RedactionList.apply(["sk-live-SECRET"], to: raw)
        #expect(!redacted.contains("sk-live-SECRET"))
        #expect(redacted.contains("[redacted]"))
        // Even after truncation the secret fragment never appears.
        #expect(!String(redacted.prefix(60)).contains("sk-live"))
    }
}
