import Foundation
import Testing

@testable import Ainkrad

/// Pure-logic coverage for Task 17's model pill (Auto/pin + curated badge) and
/// the `/usage` dashboard's cost/savings formatting — the SwiftUI layer itself
/// is verified by screenshot (per the task's screenshot gate).
@Suite("Sage model pill + usage dashboard logic")
struct SageModelDashboardTests {

    // MARK: - Auto badge

    @Test("Auto badge shows when there's no pin and the router is enabled")
    func autoBadgeShowsWithNoPinAndRouterEnabled() {
        #expect(modelPillShowsAutoBadge(pinnedModel: nil, routerEnabled: true) == true)
    }

    @Test("Auto badge hides when the user pinned a model, even with the router enabled")
    func autoBadgeHidesWhenPinned() {
        #expect(modelPillShowsAutoBadge(pinnedModel: "claude-opus-4-8", routerEnabled: true) == false)
    }

    @Test("Auto badge hides when the router is disabled, even with no pin")
    func autoBadgeHidesWhenRouterDisabled() {
        #expect(modelPillShowsAutoBadge(pinnedModel: nil, routerEnabled: false) == false)
    }

    @Test("The pill's selection sits on the Auto row exactly when the Auto badge would show")
    func selectionIsAutoMirrorsAutoBadge() {
        #expect(modelPillSelectionIsAuto(pinnedModel: nil, routerEnabled: true) == true)
        #expect(modelPillSelectionIsAuto(pinnedModel: "claude-opus-4-8", routerEnabled: true) == false)
        #expect(modelPillSelectionIsAuto(pinnedModel: nil, routerEnabled: false) == false)
    }

    // MARK: - Display model resolution

    @Test("A pin always wins the pill's displayed model")
    func pinWinsDisplayModel() {
        let displayed = modelPillDisplayModel(
            pinnedModel: "claude-haiku-4-8", routerEnabled: true,
            lastResolvedModel: "claude-opus-4-8", standingDefault: "claude-sonnet-4-8")
        #expect(displayed == "claude-haiku-4-8")
    }

    @Test("Auto (no pin, router enabled) displays the router's last-resolved model")
    func autoDisplaysLastResolvedModel() {
        let displayed = modelPillDisplayModel(
            pinnedModel: nil, routerEnabled: true,
            lastResolvedModel: "gpt-5-mini", standingDefault: "claude-sonnet-4-8")
        #expect(displayed == "gpt-5-mini")
    }

    @Test("Auto with no turn settled yet falls back to the standing default")
    func autoFallsBackBeforeFirstTurn() {
        let displayed = modelPillDisplayModel(
            pinnedModel: nil, routerEnabled: true,
            lastResolvedModel: nil, standingDefault: "claude-sonnet-4-8")
        #expect(displayed == "claude-sonnet-4-8")
    }

    @Test("Router disabled with no pin displays the standing default")
    func disabledRouterDisplaysStandingDefault() {
        let displayed = modelPillDisplayModel(
            pinnedModel: nil, routerEnabled: false,
            lastResolvedModel: "gpt-5-mini", standingDefault: "claude-sonnet-4-8")
        #expect(displayed == "claude-sonnet-4-8")
    }

    // MARK: - Curated marker

    @Test("A model in the connection's curated list is curated")
    func curatedModelIsCurated() {
        #expect(isCuratedModel("claude-opus-4-8", curatedModels: ["claude-opus-4-8", "claude-sonnet-4-8"]) == true)
    }

    @Test("A model outside the curated list is not curated")
    func nonCuratedModelIsNotCurated() {
        #expect(isCuratedModel("some-custom-model", curatedModels: ["claude-opus-4-8"]) == false)
    }

    @Test("The option row label prefixes curated models with the verified glyph")
    func optionRowLabelPrefixesCuratedGlyph() {
        #expect(
            modelOptionRowLabel(connectionName: "Claude Key", model: "claude-opus-4-8", isCurated: true)
                == "✓ Claude Key · claude-opus-4-8")
    }

    @Test("The option row label leaves non-curated models unmarked")
    func optionRowLabelLeavesNonCuratedUnmarked() {
        #expect(
            modelOptionRowLabel(connectionName: "Claude Key", model: "some-custom-model", isCurated: false)
                == "Claude Key · some-custom-model")
    }

    // MARK: - Usage dashboard cost/savings formatting

    @Test("A known positive cost formats as a dollar amount")
    func knownCostFormatsAsDollars() {
        #expect(formattedUsageCost(0.1234) == "$0.1234")
    }

    @Test("A zero/unknown cost never renders a misleading $0.0000")
    func unknownCostRendersUnknownText() {
        #expect(formattedUsageCost(0) == "cost unknown")
    }

    @Test("A negative cost (defensive) also renders as unknown, never a negative dollar amount")
    func negativeCostRendersUnknownText() {
        #expect(formattedUsageCost(-1) == "cost unknown")
    }

    @Test("Positive router savings format as a dollar amount")
    func positiveSavingsFormatsAsDollars() {
        #expect(formattedRouterSavings(0.5) == "Saved $0.5000")
    }

    @Test("Zero or nil savings render nothing (no savings line to show)")
    func zeroOrNilSavingsRenderNothing() {
        #expect(formattedRouterSavings(0) == nil)
        #expect(formattedRouterSavings(nil) == nil)
    }

    // MARK: - Usage dashboard first-run gate

    @Test("hasUsage is false when nothing has ever been tracked")
    func hasUsageFalseForZero() {
        #expect(UsageDashboardView.hasUsage(.zero) == false)
    }

    @Test("hasUsage is true when input tokens exist")
    func hasUsageTrueForInput() {
        #expect(UsageDashboardView.hasUsage(TokenUsage(input: 1)) == true)
    }

    @Test("hasUsage is true when output tokens exist")
    func hasUsageTrueForOutput() {
        #expect(UsageDashboardView.hasUsage(TokenUsage(output: 1)) == true)
    }

    @Test("hasUsage is true when only cache-read tokens exist")
    func hasUsageTrueForCacheRead() {
        #expect(UsageDashboardView.hasUsage(TokenUsage(cacheRead: 1)) == true)
    }
}
