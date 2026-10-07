import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct TodoItemTests {
    @Test func decodesItemsAndStatuses() {
        let input = JSONValue.object([
            "items": .array([
                .object(["content": .string("read spec"), "status": .string("completed")]),
                .object(["content": .string("write tool"), "status": .string("in_progress")]),
                .object(["content": .string("wire UI"), "status": .string("pending")]),
            ])
        ])
        let items = TodoItem.list(from: input)
        #expect(items.count == 3)
        #expect(items[0] == TodoItem(content: "read spec", status: .completed))
        #expect(items[1].status == .inProgress)
        #expect(items[2].status == .pending)
    }

    @Test func unknownOrMissingStatusFallsBackToPending() {
        let input = JSONValue.object([
            "items": .array([
                .object(["content": .string("x"), "status": .string("bogus")]),
                .object(["content": .string("y")]),
            ])
        ])
        let items = TodoItem.list(from: input)
        #expect(items.map(\.status) == [.pending, .pending])
    }

    @Test func skipsBlankContentAndNonObjects() {
        let input = JSONValue.object([
            "items": .array([
                .object(["content": .string("  "), "status": .string("pending")]),
                .string("garbage"),
                .object(["content": .string("keep"), "status": .string("completed")]),
            ])
        ])
        #expect(TodoItem.list(from: input) == [TodoItem(content: "keep", status: .completed)])
    }
}
