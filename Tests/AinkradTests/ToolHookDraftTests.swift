import Foundation
import Testing

@testable import Ainkrad

@Suite("ToolHook draft validation")
struct ToolHookDraftTests {
    @Test func rejectsEmptyMatchOrCommand() {
        var draft = ToolHookDraft()
        #expect(draft.validationError != nil)
        draft.match = "edit_file"
        #expect(draft.validationError != nil)  // command still empty
        draft.command = "swiftformat ."
        #expect(draft.validationError == nil)
    }

    @Test func buildsAnEnabledHook() {
        var draft = ToolHookDraft()
        draft.match = "*"
        draft.command = "echo hi"
        draft.event = .postToolUse
        draft.timeoutSeconds = 20
        let hook = draft.build()
        #expect(hook?.enabled == true)
        #expect(hook?.match == "*")
        #expect(hook?.timeoutSeconds == 20)
    }
}
