import AinkradHostRuntime
import Foundation

/// Persisted root directory for the `@`-mention file index (M7 Slice 5c Task 22).
/// Defaults to the user's home directory until a later folder-picker (Task 22b,
/// not built here) lets the user change it.
struct SageWorkspaceSettings: PersistableDocument {
    static let documentID = "assistant-workspace"
    var workingDirectoryPath: String

    init(workingDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.workingDirectoryPath = workingDirectoryPath
    }
}
