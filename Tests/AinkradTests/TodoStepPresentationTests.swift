import Foundation
import Testing

@testable import Ainkrad

@Suite struct TodoStepPresentationTests {
    @Test func glyphPerStatus() {
        #expect(TodoStepPresentation.glyph(.pending) == "circle")
        #expect(TodoStepPresentation.glyph(.inProgress) == "circle.lefthalf.filled")
        #expect(TodoStepPresentation.glyph(.completed) == "checkmark.circle.fill")
    }

    @Test func doneFlag() {
        #expect(TodoStepPresentation.isDone(.completed))
        #expect(!TodoStepPresentation.isDone(.pending))
        #expect(!TodoStepPresentation.isDone(.inProgress))
    }

    @Test func progressSummary() {
        let items = [
            TodoItem(content: "a", status: .completed),
            TodoItem(content: "b", status: .completed),
            TodoItem(content: "c", status: .pending),
        ]
        #expect(TodoStepPresentation.summary(items) == "2 / 3")
    }
}
