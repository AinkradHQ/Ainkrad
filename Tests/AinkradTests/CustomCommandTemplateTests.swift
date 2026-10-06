import Foundation
import Testing

@testable import Ainkrad

@Suite("CustomCommandTemplate")
struct CustomCommandTemplateTests {
    @Test func expandsAllArguments() {
        #expect(
            CustomCommandTemplate.expand("Fix $ARGUMENTS", arguments: "the login bug")
                == "Fix the login bug")
    }

    @Test func expandsPositionalArguments() {
        #expect(
            CustomCommandTemplate.expand("Deploy $1 to $2", arguments: "app staging")
                == "Deploy app to staging")
    }

    @Test func missingPositionalBecomesEmpty() {
        #expect(
            CustomCommandTemplate.expand("Deploy $1 to $2", arguments: "app")
                == "Deploy app to ")
    }

    @Test func doubleDollarIsLiteralDollar() {
        #expect(
            CustomCommandTemplate.expand("Cost is $$5 for $1", arguments: "coffee")
                == "Cost is $5 for coffee")
    }

    /// `½` and Arabic-Indic `٠` are numeric but name no positional slot: they stay verbatim
    /// rather than trapping on a missing `wholeNumberValue` or indexing `positional[-1]`.
    @Test func nonWholeOrZeroNumericAfterDollarLeftAlone() {
        #expect(CustomCommandTemplate.expand("$½ and $\u{0660}", arguments: "a") == "$½ and $\u{0660}")
    }

    @Test func nonPlaceholderDollarLeftAlone() {
        #expect(
            CustomCommandTemplate.expand("var x = $foo", arguments: "")
                == "var x = $foo")
    }

    @Test func splitsOnGeneralWhitespace() {
        #expect(
            CustomCommandTemplate.expand("Deploy $1 to $2", arguments: "app\tstaging")
                == "Deploy app to staging")
    }
}
