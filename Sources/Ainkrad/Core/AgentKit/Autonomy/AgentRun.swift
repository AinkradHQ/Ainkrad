import AinkradHostRuntime
import Foundation

/// What kicked off an `AgentRun`.
enum AgentRunOrigin: String, Codable, Equatable, Sendable {
    case chat
    case schedule
    case event
}

/// Lifecycle state of an `AgentRun`.
enum AgentRunStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case paused
    case done
    case failed
    case interrupted
}

/// A first-class, persistable unit of autonomous work. Survives relaunch via
/// `AgentRunsDocument`; `RunManager` owns lifecycle.
struct AgentRun: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var origin: AgentRunOrigin
    var prompt: String
    var status: AgentRunStatus
    var logs: [String]
    var result: String?
    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    /// M7 Wave B (Slice 3b follow-up): the schedule/trigger's own saved
    /// permission/sandbox posture, projected onto this specific run so
    /// `BackgroundRunRunner`/`AgentSession` can narrow the effective mode and
    /// sandbox profile for THIS run rather than always inheriting the shared
    /// background default. `nil` for `.chat` runs (no schedule to inherit
    /// from) and for any old persisted run predating this field.
    var posture: SavedExecutionPosture?

    init(
        id: UUID = UUID(), origin: AgentRunOrigin = .chat, prompt: String,
        status: AgentRunStatus = .queued, logs: [String] = [], result: String? = nil,
        createdAt: Date = Date(), startedAt: Date? = nil, finishedAt: Date? = nil,
        posture: SavedExecutionPosture? = nil
    ) {
        self.id = id
        self.origin = origin
        self.prompt = prompt
        self.status = status
        self.logs = logs
        self.result = result
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.posture = posture
    }

    // Forward-compatible decode (wave-1 idiom, mirrors GlobalSettings): tolerate
    // payloads missing fields a newer/older build didn't write. `id` is the only
    // strictly required key; everything else — including `createdAt` — falls
    // back to a default so legacy/future payloads never throw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        origin = try container.decodeIfPresent(AgentRunOrigin.self, forKey: .origin) ?? .chat
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        status = try container.decodeIfPresent(AgentRunStatus.self, forKey: .status) ?? .queued
        logs = try container.decodeIfPresent([String].self, forKey: .logs) ?? []
        result = try container.decodeIfPresent(String.self, forKey: .result)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        posture = try container.decodeIfPresent(SavedExecutionPosture.self, forKey: .posture) ?? nil
    }
}

/// The persisted collection of `AgentRun`s — survives app relaunch.
/// `RunManager` (Task 3) owns reads/writes.
struct AgentRunsDocument: PersistableDocument {
    static let documentID = "agent-runs"
    var runs: [AgentRun] = []

    init(runs: [AgentRun] = []) {
        self.runs = runs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runs = try container.decodeIfPresent([AgentRun].self, forKey: .runs) ?? []
    }
}
