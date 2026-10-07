import Foundation

/// Pure, validatable draft for the add/edit form — keeps validation testable
/// without SwiftUI.
struct ToolHookDraft: Equatable {
    var event: ToolHookEvent = .postToolUse
    var match: String = ""
    var command: String = ""
    var timeoutSeconds: Int = 30

    /// Recomputed from the current fields on every access, so mutating
    /// `match`/`command`/`timeoutSeconds` directly keeps this in sync
    /// without any explicit setter plumbing.
    var validationError: String? {
        if match.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter a tool-name match (e.g. edit_file or *)."
        }
        if command.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a shell command to run." }
        if timeoutSeconds <= 0 { return "Timeout must be positive." }
        return nil
    }

    func build() -> ToolHook? {
        guard validationError == nil else { return nil }
        return ToolHook(
            id: UUID(), enabled: true, event: event,
            match: match.trimmingCharacters(in: .whitespaces),
            command: command.trimmingCharacters(in: .whitespaces),
            timeoutSeconds: timeoutSeconds)
    }
}
