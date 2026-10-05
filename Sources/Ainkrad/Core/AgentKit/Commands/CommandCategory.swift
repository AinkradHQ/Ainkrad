import Foundation

/// Grouping bucket for a `SlashCommand`, used to render the command palette in
/// ordered sections. Host-internal (no SDK type touched). `.other` is the
/// default so an un-tagged or future command never fails to compile or vanish.
enum CommandCategory: String, CaseIterable, Sendable {
    case session
    case model
    case info
    case memory
    case skill
    case custom
    case other

    /// Section header text shown in the palette.
    var title: String {
        switch self {
        case .session: return "Session"
        case .model: return "Model"
        case .info: return "Info"
        case .memory: return "Memory"
        case .skill: return "Skills"
        case .custom: return "Commands"
        case .other: return "Other"
        }
    }

    /// Stable section sort order (lower shows first).
    var order: Int {
        switch self {
        case .session: return 0
        case .model: return 1
        case .info: return 2
        case .memory: return 3
        case .skill: return 4
        case .custom: return 5
        case .other: return 6
        }
    }
}
