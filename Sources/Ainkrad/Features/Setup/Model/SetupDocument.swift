import AinkradHostRuntime
import Foundation

/// Records that first-run setup finished, at which version, and which steps the
/// user was allowed to walk past without satisfying.
///
/// Versioning is what lets a later release add a step and re-gate on only that
/// step, instead of replaying the whole wizard for existing users.
/// `deferredSteps` reuses exactly that machinery for a different reason: a step
/// the user postponed is *owed* in precisely the same sense as a step introduced
/// after their last completion, and `SetupCoordinator` resolves both through the
/// same filter rather than growing a parallel mechanism. The marker is written
/// as "completed, but still owing X" — never as "not completed" (which would
/// replay the whole wizard) and never as "completed" outright (which would
/// forget silently).
struct SetupDocument: PersistableDocument {
    static let documentID = "setup"

    var completedAt: Date?
    var setupVersion: Int
    /// `SetupStep.rawValue`s the user deferred. Stored as strings so an unknown
    /// value from a newer build round-trips instead of failing to decode; the
    /// coordinator maps back and drops anything it does not recognise.
    var deferredSteps: [String]

    init(completedAt: Date? = nil, setupVersion: Int = 0, deferredSteps: [String] = []) {
        self.completedAt = completedAt
        self.setupVersion = setupVersion
        self.deferredSteps = deferredSteps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        setupVersion = try c.decodeIfPresent(Int.self, forKey: .setupVersion) ?? 0
        // Absent in every marker written before deferral existed — those users
        // owe nothing, so an empty list is the correct reading.
        deferredSteps = try c.decodeIfPresent([String].self, forKey: .deferredSteps) ?? []
    }

    enum CodingKeys: String, CodingKey { case completedAt, setupVersion, deferredSteps }
}
