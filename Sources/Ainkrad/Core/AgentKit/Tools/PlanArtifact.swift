import AinkradHostRuntime
import Foundation

/// One ordered step of an agent-authored plan.
struct PlanStep: Equatable, Sendable, Identifiable {
    let title: String
    /// Stable within a single plan — the title is the natural key.
    var id: String { title }
}

/// A structured plan emitted by the Plan persona via `present_plan`: a short
/// summary plus an ordered list of steps. Reconstructed from the transcript by
/// `TranscriptTimelineBuilder`; never a separate mutable store.
struct PlanArtifact: Equatable, Sendable {
    let summary: String
    let steps: [PlanStep]
}

extension PlanArtifact {
    /// Decode `{ summary?: string, steps: [ { title } | "title" ] }`. Blank-title
    /// entries are dropped; a missing/empty `steps` array yields `nil` (there is no
    /// plan to present). `summary` defaults to "".
    static func from(_ input: JSONValue) -> PlanArtifact? {
        guard case .array(let raw)? = input["steps"] else { return nil }
        let steps: [PlanStep] = raw.compactMap { entry in
            let rawTitle = entry.stringValue ?? entry["title"]?.stringValue
            guard let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else { return nil }
            return PlanStep(title: title)
        }
        guard !steps.isEmpty else { return nil }
        let summary =
            input["summary"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PlanArtifact(summary: summary, steps: steps)
    }
}
