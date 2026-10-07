import Foundation

/// Per-step required fields.
///
/// Required means *Continue is disabled and the reason is visible beside the
/// field* — never a silent no-op. A disabled button at the other end of the
/// screen with nothing explaining it is the failure mode this exists to
/// prevent, so every rule here carries user-facing copy, not just a Bool.
///
/// Steps whose controls all have real defaults already applied live
/// (Appearance, Motion & Sound) are deliberately never blocking: there is
/// nothing for the user to supply. Home and Providers enforce their
/// requirement structurally — a vault must be adopted, a connection must pass
/// a live probe — so they have no field-level rule here either.
///
/// The `[String: String]` shape keeps this pure and testable: no SwiftUI, no
/// stores. Each step's view builds the dictionary from its own `@State` (the
/// Sage step's `isCustom` lives in the view, and arrives here as
/// `"isCustom": "true"`).
///
/// Steps whose requirement is STRUCTURAL rather than a text field — Home wants
/// an adopted folder, Providers wants a connection that passed a live probe —
/// are expressed here too, as a flag in the same dictionary
/// (`"hasHome"`, `"isConnected"`). They were briefly left out on the grounds
/// that a probe result "isn't a field"; that was wrong on both counts. The
/// Sage step already passes pure view state (`isCustom`) the same way, so
/// the shape never needed to flex — and leaving them out made `canAdvance`
/// return `true` for two steps the UI blocks, which is a trap for any future
/// caller that reads the function's name and believes it.
enum SetupValidation {
    struct Requirement: Equatable {
        let field: String
        let message: String
    }

    static func unmet(for step: SetupStep, values: [String: String]) -> [Requirement] {
        func blank(_ key: String) -> Bool {
            (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        switch step {
        case .you:
            var unmet: [Requirement] = []
            if blank("name") {
                unmet.append(
                    Requirement(
                        field: "name",
                        message: "Your assistant needs something to call you."))
            }
            if blank("role") {
                unmet.append(
                    Requirement(
                        field: "role",
                        message: "What you do shapes how the assistant helps."))
            }
            // `timezone` is prefilled from `TimeZone.current` but deliberately
            // not required: a user may clear it, and being unable to continue
            // because of a field they never typed in would be absurd.
            return unmet

        case .assistant:
            guard values["isCustom"] == "true" else { return [] }
            var unmet: [Requirement] = []
            if blank("personaName") {
                unmet.append(Requirement(field: "personaName", message: "Give your assistant a name."))
            }
            if blank("personaInstructions") {
                unmet.append(
                    Requirement(
                        field: "personaInstructions",
                        message: "Describe how it should work."))
            }
            return unmet

        case .home:
            // Enforced structurally in the view too (the step advances only on a
            // successful adoption), but stated here so `canAdvance` tells the
            // truth for this step rather than waving it through.
            guard values["hasHome"] != "true" else { return [] }
            return [
                Requirement(
                    field: "hasHome",
                    message: "Choose a folder for your Ainkrad Home to continue.")
            ]

        case .providers:
            guard values["isConnected"] != "true" else { return [] }
            // The escape hatch, and the ONLY thing that satisfies this step
            // without a live probe. It is offered by the view solely for a
            // failure the user cannot fix (`ConnectionFailure.allowsDeferral`) — the rule
            // for *when* it may be set lives with the classification, not here;
            // this only honours a decision already made. The step stays owed:
            // `SetupCoordinator.setDeferred` records it in the marker so the
            // gate re-raises on this step at the next launch.
            guard values["isDeferred"] != "true" else { return [] }
            return [
                Requirement(
                    field: "isConnected",
                    message: "Connect a provider above to continue — the connection is checked "
                        + "before Ainkrad accepts it.")
            ]

        case .welcome, .appearance, .motionAndSound, .done:
            return []
        }
    }

    static func canAdvance(from step: SetupStep, values: [String: String]) -> Bool {
        unmet(for: step, values: values).isEmpty
    }
}
