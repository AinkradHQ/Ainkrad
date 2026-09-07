import Testing
import Foundation
@testable import Ainkrad
import AinkradAppKitContract

@Suite("Settings composes the kit")
@MainActor
struct SettingsKitCompositionTests {
    /// Repo-relative source roots. Resolved from this file's location so the
    /// test works regardless of where the checkout lives.
    private static func sourceText(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)                 // Tests/AinkradTests/…
        let repo = here.deletingLastPathComponent()                 // AinkradTests
            .deletingLastPathComponent()                            // Tests
            .deletingLastPathComponent()                            // repo root
        return try String(contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("no settings source hand-rolls a search field or a result list")
    func noLookAlikeComponents() throws {
        let banned = ["SettingsSearchField", "SettingsPaletteRow"]
        let overlay = try Self.sourceText("Sources/Ainkrad/Features/Settings/Views/SettingsOverlayView.swift")
        for name in banned {
            #expect(!overlay.contains("struct \(name)"),
                    "\(name) is a look-alike of a kit component — compose the kit instead")
        }
        #expect(overlay.contains("AinkradSearchField"),
                "the overlay must use the kit's search field")
    }

    @Test("settings sources declare no private spacing scale")
    func noPrivateSpacingScale() throws {
        // Asserted on HOST sources only. An earlier draft of this test reached
        // into ../AinkradAppKit, which resolves correctly from the main
        // checkout but NOT from a git worktree under .claude/worktrees/ —
        // the SDK is a sibling of the checkout, not of the worktree. The kit
        // side is covered by its own `swift test` instead.
        let overlay = try Self.sourceText("Sources/Ainkrad/Features/Settings/Views/SettingsOverlayView.swift")
        let bannedLiterals = [".padding(14)", ".padding(18)", ".padding(24)", "spacing: 14", "spacing: 18"]
        for literal in bannedLiterals {
            #expect(!overlay.contains(literal),
                    "\(literal) is a private spacing constant — use AinkradSpacing")
        }
    }

    @Test("RATCHET: the .custom field count may not grow")
    func customRatchet() {
        // Measured against the live catalog. Raising this ceiling requires a
        // deliberate edit and a reason — that is the point; it only works if
        // decomposition work TIGHTENS it.
        //
        // History:
        //   23  start of Task 6.
        //   22  Task 7 decomposed BOTH Sound and Voice.
        //   23  Sound reverted at the review gate — one field per control made
        //       each of 13 sound events three near-duplicate rows. Voice stayed
        //       decomposed (−1 pane), Sound came back (+1 pane), net 23.
        //   24  Task 10 added the You page — one `.custom` field
        //       (`UserProfileSettingsView`) hosting the four profile facts as a
        //       single unit, deliberately, for the same reason Sound stayed a
        //       pane: one row per fact would just be four near-identical text
        //       fields with no shared framing.
        //   25  Task 11 added the Home group to General — one `.custom` field
        //       (`HomeSettingsView`) showing the wizard-adopted vault location
        //       (path + Reveal in Finder) as a single read-only unit, for the
        //       same reason: it is not a control to decompose, it is a fact
        //       with an action attached.
        //
        //   26  M3 added the Notifications page — one `.custom` field
        //       (`NotificationsSettingsView`) hosting `SignalSettingsPane`.
        //
        //       This one is a WEAKER justification than the three above, and
        //       recording that honestly matters more than defending it. Sound,
        //       You and Home are genuinely not decomposable: one field per
        //       control would produce near-duplicate rows, or the content is a
        //       fact rather than a control. Notifications is NOT like that —
        //       its delivery toggles and retention steppers map cleanly onto
        //       `.toggle` and `.stepper` fields, and only the cross-app access
        //       section actually needs a custom view.
        //
        //       It is a `.custom` because the pane already existed, was
        //       designed and screenshot-approved as a pane in M1, and
        //       decomposing it now would redesign reviewed UI in a task about
        //       permissions. The debt is real: converting it should leave ONE
        //       custom field (cross-app access) and four descriptor fields,
        //       which is a net improvement rather than a wash.
        //
        // So this is a HOLD except for those deliberate additions: it may not
        // grow past 26 without a similar reason. It drops again when the SDK
        // gains a composite row kind and Sound can be converted properly — see
        // the note in `HostSettingsCatalog`, and when Notifications is
        // decomposed as described above.
        let ceiling = 26
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let customCount = catalog.allFields.filter {
            if case .custom = $0.kind { return true }
            return false
        }.count
        let message = "\(customCount) .custom fields exceeds the ceiling of \(ceiling); "
            + "wrap-a-view is the decay mode this design warns about"
        #expect(customCount <= ceiling, "\(message)")
    }
}
