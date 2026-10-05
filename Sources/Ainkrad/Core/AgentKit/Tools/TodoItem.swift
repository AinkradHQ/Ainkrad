import AinkradHostRuntime
import Foundation

/// One entry in the agent's per-session task checklist.
struct TodoItem: Equatable, Sendable, Identifiable {
    enum Status: String, Equatable, Sendable, CaseIterable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
    let content: String
    let status: Status
    /// Stable within a single list — content is the natural key the agent revises against.
    var id: String { content }
}

extension TodoItem {
    /// Decode `{ items: [ { content, status } ] }`. Non-object entries and
    /// blank-content entries are dropped; unknown/missing status → `.pending`.
    static func list(from input: JSONValue) -> [TodoItem] {
        guard case .array(let raw)? = input["items"] else { return [] }
        return raw.compactMap { entry in
            guard let content = entry["content"]?.stringValue,
                !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let status = entry["status"]?.stringValue.flatMap(Status.init(rawValue:)) ?? .pending
            return TodoItem(content: content, status: status)
        }
    }
}
