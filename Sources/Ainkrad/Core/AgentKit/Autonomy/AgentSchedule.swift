import AinkradHostRuntime
import Foundation

/// A payload-carrying enum with a hand-written `Codable` conformance (M7 Wave
/// B): a future case this build doesn't know yet must decode to `.unknown`
/// rather than throwing and losing the whole `AgentSchedule` (and everything
/// else in the same `SchedulesDocument`). The synthesized-rawValue trick used
/// elsewhere (e.g. `ScryElementKind`) doesn't apply here since these cases
/// carry associated values — instead each known case's keyed payload is
/// attempted in turn, falling back to `.unknown` only once none match.
///
/// `.webhook` intentionally carries NO id (M7 Wave B / B3 fix): the real
/// webhook path (`WebhookServer` → `TriggerEvent.scheduleID` →
/// `TriggerDispatcher.fire` matching `$0.id == event.scheduleID`) has always
/// keyed off the OWNING `AgentSchedule.id`, never this case's payload — a
/// separate random id here could only ever diverge from it, never be read.
enum ScheduleTrigger: Codable, Equatable, Sendable {
    case time(cron: CronExpression)
    case fileChange(path: String, glob: String?)
    case gitChange(repoPath: String)
    case webhook
    /// Forward-compat placeholder for a trigger kind this build doesn't
    /// recognize (M7 Wave B / B2). Never constructed by this build's own
    /// code — only ever produced by decoding a newer/foreign payload.
    case unknown

    private enum CodingKeys: String, CodingKey {
        case time, fileChange, gitChange, webhook, unknown
    }
    private enum TimeKeys: String, CodingKey { case cron }
    private enum FileChangeKeys: String, CodingKey { case path, glob }
    private enum GitChangeKeys: String, CodingKey { case repoPath }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.nestedContainer(keyedBy: TimeKeys.self, forKey: .time) {
            self = .time(cron: try nested.decode(CronExpression.self, forKey: .cron))
            return
        }
        if let nested = try? container.nestedContainer(keyedBy: FileChangeKeys.self, forKey: .fileChange) {
            self = .fileChange(
                path: try nested.decode(String.self, forKey: .path),
                glob: try nested.decodeIfPresent(String.self, forKey: .glob))
            return
        }
        if let nested = try? container.nestedContainer(keyedBy: GitChangeKeys.self, forKey: .gitChange) {
            self = .gitChange(repoPath: try nested.decode(String.self, forKey: .repoPath))
            return
        }
        if container.contains(.webhook) {
            self = .webhook
            return
        }
        // Unrecognized (a future case, or a stale `.webhook(id:)` payload from
        // before this fix — its keyed `id` string doesn't match any container
        // above): forward-compat, never throw.
        self = .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .time(let cron):
            var nested = container.nestedContainer(keyedBy: TimeKeys.self, forKey: .time)
            try nested.encode(cron, forKey: .cron)
        case .fileChange(let path, let glob):
            var nested = container.nestedContainer(keyedBy: FileChangeKeys.self, forKey: .fileChange)
            try nested.encode(path, forKey: .path)
            try nested.encodeIfPresent(glob, forKey: .glob)
        case .gitChange(let repoPath):
            var nested = container.nestedContainer(keyedBy: GitChangeKeys.self, forKey: .gitChange)
            try nested.encode(repoPath, forKey: .repoPath)
        case .webhook:
            try container.encode(true, forKey: .webhook)
        case .unknown:
            // `.unknown` is never constructed by THIS build's own code — only
            // by decoding a payload it didn't understand. Re-encoding it as a
            // stable placeholder (rather than round-tripping the original
            // unrecognized payload, which this decoder never captured) is a
            // deliberate, documented no-op: the schedule is simply skipped by
            // every switch this build has (`ScheduleRunner`, the trigger-watch
            // loop) either way.
            try container.encode(true, forKey: .unknown)
        }
    }
}

/// The explicit, saved permission/sandbox posture a schedule runs with. Set at
/// creation; the scheduler never escalates beyond it.
struct SavedExecutionPosture: Codable, Equatable, Sendable {
    var permissionMode: String  // AgentPermissionMode.rawValue
    var sandboxProfileID: String?  // PROVISIONAL — projects into Slice 6 AgentExecutionPolicy

    init(permissionMode: String, sandboxProfileID: String? = nil) {
        self.permissionMode = permissionMode
        self.sandboxProfileID = sandboxProfileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        permissionMode = try c.decodeIfPresent(String.self, forKey: .permissionMode) ?? "ask"
        sandboxProfileID = try c.decodeIfPresent(String.self, forKey: .sandboxProfileID)
    }
}

struct AgentSchedule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var trigger: ScheduleTrigger
    var prompt: String
    var agentID: UUID?
    var enabled: Bool
    var posture: SavedExecutionPosture
    var lastFired: Date?
    var lastRunID: UUID?

    init(
        id: UUID = UUID(), name: String, trigger: ScheduleTrigger, prompt: String,
        agentID: UUID? = nil, enabled: Bool = true, posture: SavedExecutionPosture,
        lastFired: Date? = nil, lastRunID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.prompt = prompt
        self.agentID = agentID
        self.enabled = enabled
        self.posture = posture
        self.lastFired = lastFired
        self.lastRunID = lastRunID
    }

    // Forward-compatible decode (wave-1 idiom). `id`/`name`/`trigger`/`prompt`/`posture`
    // are required identity; the rest tolerate absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        trigger = try c.decode(ScheduleTrigger.self, forKey: .trigger)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        agentID = try c.decodeIfPresent(UUID.self, forKey: .agentID)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        posture = try c.decode(SavedExecutionPosture.self, forKey: .posture)
        lastFired = try c.decodeIfPresent(Date.self, forKey: .lastFired)
        lastRunID = try c.decodeIfPresent(UUID.self, forKey: .lastRunID)
    }
}

struct SchedulesDocument: PersistableDocument {
    static let documentID = "agent-schedules"
    var schedules: [AgentSchedule] = []

    init(schedules: [AgentSchedule] = []) { self.schedules = schedules }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedules = try c.decodeIfPresent([AgentSchedule].self, forKey: .schedules) ?? []
    }
}
