import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct PlanArtifactTests {
    @Test func decodesSummaryAndOrderedSteps() {
        let input = JSONValue.object([
            "summary": .string("Refactor the parser"),
            "steps": .array([
                .object(["title": .string("Read the grammar file")]),
                .object(["title": .string("Extract the lexer")]),
                .object(["title": .string("Add tests")]),
            ]),
        ])
        let plan = PlanArtifact.from(input)
        #expect(plan?.summary == "Refactor the parser")
        #expect(
            plan?.steps == [
                PlanStep(title: "Read the grammar file"),
                PlanStep(title: "Extract the lexer"),
                PlanStep(title: "Add tests"),
            ])
    }

    @Test func acceptsBareStringSteps() {
        let input = JSONValue.object(["steps": .array([.string("Do A"), .string("Do B")])])
        let plan = PlanArtifact.from(input)
        #expect(plan?.summary == "")
        #expect(plan?.steps.map(\.title) == ["Do A", "Do B"])
    }

    @Test func skipsBlankStepsAndNilWhenEmpty() {
        #expect(PlanArtifact.from(.object(["steps": .array([])])) == nil)
        #expect(PlanArtifact.from(.object(["summary": .string("x")])) == nil)  // no steps key
        let mixed = JSONValue.object([
            "steps": .array([
                .object(["title": .string("  ")]),
                .string("garbage-kept"),
                .object(["title": .string("keep")]),
            ])
        ])
        #expect(PlanArtifact.from(mixed)?.steps.map(\.title) == ["garbage-kept", "keep"])
    }
}
