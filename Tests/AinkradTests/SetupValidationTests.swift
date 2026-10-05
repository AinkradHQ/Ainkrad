import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup validation")
struct SetupValidationTests {
    @Test func theYouStepRequiresNameAndRole() {
        #expect(!SetupValidation.canAdvance(from: .you, values: [:]))
        #expect(!SetupValidation.canAdvance(from: .you, values: ["name": "Ahmed"]))
        #expect(SetupValidation.canAdvance(from: .you, values: ["name": "Ahmed", "role": "Engineer"]))
    }

    @Test func whitespaceIsNotAValue() {
        #expect(!SetupValidation.canAdvance(from: .you, values: ["name": "  ", "role": "\n"]))
    }

    @Test func unmetRequirementsNameTheFieldAndExplain() {
        let unmet = SetupValidation.unmet(for: .you, values: ["role": "Engineer"])
        #expect(unmet.map(\.field) == ["name"])
        #expect(!(unmet.first?.message.isEmpty ?? true))
    }

    /// Timezone is prefilled from `TimeZone.current`, but a user may clear it —
    /// it must never be what stands between them and Continue.
    @Test func timezoneIsNotRequired() {
        #expect(
            SetupValidation.canAdvance(
                from: .you,
                values: [
                    "name": "Ahmed", "role": "Engineer",
                    "timezone": "",
                ]))
    }

    // A custom persona is only required to be complete if the user chose one.
    @Test func theAssistantStepOnlyRequiresACustomPersonaWhenCustom() {
        #expect(SetupValidation.canAdvance(from: .assistant, values: [:]))
        #expect(
            !SetupValidation.canAdvance(
                from: .assistant,
                values: ["isCustom": "true", "personaName": "Scribe"]))
        #expect(
            SetupValidation.canAdvance(
                from: .assistant,
                values: [
                    "isCustom": "true", "personaName": "Scribe",
                    "personaInstructions": "Be terse.",
                ]))
    }

    @Test func theAssistantStepNamesBothMissingCustomFields() {
        let unmet = SetupValidation.unmet(for: .assistant, values: ["isCustom": "true"])
        #expect(unmet.map(\.field) == ["personaName", "personaInstructions"])
    }

    // Appearance and Motion apply live defaults, so they are never blocking.
    @Test func stepsWithLiveDefaultsNeverBlock() {
        for step in [SetupStep.welcome, .appearance, .motionAndSound, .done] {
            #expect(SetupValidation.canAdvance(from: step, values: [:]))
            #expect(SetupValidation.unmet(for: step, values: [:]).isEmpty)
        }
    }

    /// Home and Providers enforce their requirement structurally rather than
    /// through a text field — but `canAdvance` must still say so, or a caller
    /// that trusts the function's name walks a user past Providers with no
    /// connection at all.
    @Test func providersRequiresAVerifiedConnection() {
        #expect(!SetupValidation.canAdvance(from: .providers, values: [:]))
        #expect(!SetupValidation.canAdvance(from: .providers, values: ["isConnected": "false"]))
        #expect(SetupValidation.canAdvance(from: .providers, values: ["isConnected": "true"]))
    }

    @Test func homeRequiresAnAdoptedFolder() {
        #expect(!SetupValidation.canAdvance(from: .home, values: [:]))
        #expect(!SetupValidation.canAdvance(from: .home, values: ["hasHome": "false"]))
        #expect(SetupValidation.canAdvance(from: .home, values: ["hasHome": "true"]))
    }

    /// Structural or not, an unmet requirement carries user-facing copy — the
    /// whole point is that the reason is visible, never a silent no-op.
    @Test func everyUnmetRequirementCarriesAMessage() {
        for step in SetupStep.allCases {
            for requirement in SetupValidation.unmet(for: step, values: ["isCustom": "true"]) {
                #expect(!requirement.field.isEmpty)
                #expect(
                    !requirement.message.isEmpty,
                    "\(step.rawValue).\(requirement.field) blocks with no explanation")
            }
        }
    }

    /// The one step whose requirement is not expressible as a value would be a
    /// hole in `canAdvance`. There is none: every blocking step is covered.
    @Test func canAdvanceIsTrueForEveryStepOnceItsValuesAreSatisfied() {
        let satisfied = [
            "name": "Ahmed", "role": "Engineer",
            "hasHome": "true", "isConnected": "true",
            "isCustom": "true", "personaName": "Scribe",
            "personaInstructions": "Be terse.",
        ]
        for step in SetupStep.allCases {
            #expect(
                SetupValidation.canAdvance(from: step, values: satisfied),
                "\(step.rawValue) blocks even when every value is supplied")
        }
    }

    // MARK: - Deferral (task 8)

    /// The step stays required by default: nothing but a live probe — or an
    /// explicit deferral — satisfies it.
    @Test func theProvidersStepBlocksWithNeitherAConnectionNorADeferral() {
        #expect(!SetupValidation.canAdvance(from: .providers, values: [:]))
        #expect(
            !SetupValidation.canAdvance(
                from: .providers, values: ["isConnected": "false", "isDeferred": "false"]))
    }

    /// "Set this up later" is what lets the user past — and it is the ONLY thing
    /// besides a real connection that does.
    @Test func adeferralSatisfiesTheProvidersStep() {
        #expect(SetupValidation.canAdvance(from: .providers, values: ["isDeferred": "true"]))
        #expect(SetupValidation.canAdvance(from: .providers, values: ["isConnected": "true"]))
    }
}
