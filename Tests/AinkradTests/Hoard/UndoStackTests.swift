import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("UndoStack")
struct UndoStackTests {
    private func entry(_ label: String) -> InverseOperation {
        InverseOperation(
            label: label, action: .delete([URL(fileURLWithPath: "/x/\(label)")]),
            recordedAt: Date(), affectedURLs: [URL(fileURLWithPath: "/x/\(label)")])
    }

    @Test("starts empty with nothing to undo or redo")
    func startsEmpty() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        #expect(!stack.canUndo)
        #expect(!stack.canRedo)
        #expect(stack.undoLabel == nil)
    }

    @Test("push then pop returns the most recent entry")
    func pushPop() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        stack.push(entry("first"))
        stack.push(entry("second"))
        #expect(stack.canUndo)
        #expect(stack.undoLabel == "second")
        #expect(stack.popForUndo()?.label == "second")
        #expect(stack.popForUndo()?.label == "first")
        #expect(!stack.canUndo)
    }

    @Test("redo becomes available after an undo")
    func redoAfterUndo() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        stack.push(entry("op"))
        let popped = stack.popForUndo()!
        stack.pushRedo(popped)
        #expect(stack.canRedo)
        #expect(stack.redoLabel == "op")
        #expect(stack.popForRedo()?.label == "op")
        #expect(!stack.canRedo)
    }

    // Without this, an undo followed by a NEW operation would leave a redo
    // entry that reapplies work from an abandoned branch of history.
    @Test("a new push clears the redo stack")
    func pushClearsRedo() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        stack.push(entry("first"))
        stack.pushRedo(stack.popForUndo()!)
        #expect(stack.canRedo)
        stack.push(entry("new"))
        #expect(!stack.canRedo)
    }

    @Test("the stack caps at 100 entries, dropping the oldest")
    func capsAt100() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        for index in 0..<105 { stack.push(entry("op\(index)")) }
        #expect(stack.entries.count == 100)
        #expect(stack.entries.first?.label == "op5")
        #expect(stack.entries.last?.label == "op104")
    }

    @Test("both stacks survive a relaunch")
    func persists() {
        let persistence = InMemoryPersistenceStore()
        let stack = UndoStack(persistence: persistence)
        stack.push(entry("kept"))
        stack.pushRedo(entry("redoable"))

        let restored = UndoStack(persistence: persistence)
        #expect(restored.undoLabel == "kept")
        #expect(restored.redoLabel == "redoable")
    }

    @Test("clear empties both stacks")
    func clear() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        stack.push(entry("a"))
        stack.pushRedo(entry("b"))
        stack.clear()
        #expect(!stack.canUndo)
        #expect(!stack.canRedo)
    }

    @Test("dropping an entry removes it without disturbing the rest")
    func dropEntry() {
        let stack = UndoStack(persistence: InMemoryPersistenceStore())
        let doomed = entry("gone")
        stack.push(entry("kept"))
        stack.push(doomed)
        stack.drop(doomed.id)
        #expect(stack.entries.map(\.label) == ["kept"])
    }
}
