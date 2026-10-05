import Foundation

/// The prompt sent when the user accepts a skill-capture suggestion. It asks
/// the model to reflect on the turn it just completed and, if the procedure is
/// genuinely reusable, call `propose_skill` (drafting to `_proposed/` for the
/// user's approval — it does NOT install anything). Names the tools the advisor
/// saw so the draft is grounded in what actually happened.
enum SkillReflectionDirective {
    static func build(toolNames: [String]) -> String {
        let tools = toolNames.joined(separator: ", ")
        return """
            Reflect on the procedure you just completed (it used: \(tools)). If — and only if — it is a \
            general, reusable workflow worth repeating, call the `propose_skill` tool to draft it (use a \
            lowercase-hyphenated name). If a similar skill already exists, improve it instead by passing \
            its name as both "name" and "improves". The draft is saved for my review and will NOT take \
            effect until I approve it. If it is not reusable, just say so briefly and do nothing.
            """
    }
}
