import Foundation
import Testing

@testable import Ainkrad

@Suite struct PlanStepPresentationTests {
    @Test func oneBasedNumbering() {
        #expect(PlanStepPresentation.number(0) == "1")
        #expect(PlanStepPresentation.number(4) == "5")
    }

    @Test func pluralizedCount() {
        #expect(PlanStepPresentation.stepCountLabel(1) == "1 step")
        #expect(PlanStepPresentation.stepCountLabel(3) == "3 steps")
        #expect(PlanStepPresentation.stepCountLabel(0) == "0 steps")
    }
}
