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
