import AinkradHostRuntime
import Foundation

struct SavedSession: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [AgentMessage]

    init(
        id: UUID = UUID(), title: String = "New chat",
        createdAt: Date, updatedAt: Date, messages: [AgentMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct SageSessionsDocument: PersistableDocument {
    static let documentID = "assistant-sessions"
    var sessions: [SavedSession] = []
    var activeID: UUID?

    init(sessions: [SavedSession] = [], activeID: UUID? = nil) {
        self.sessions = sessions
        self.activeID = activeID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decodeIfPresent([SavedSession].self, forKey: .sessions) ?? []
        activeID = try c.decodeIfPresent(UUID.self, forKey: .activeID)
    }
}
