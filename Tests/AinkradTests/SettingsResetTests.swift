import AinkradAppKitContract
import SwiftUI
import Testing

@testable import Ainkrad

/// Unit tests for `SettingsPage.resettableFields` / `resetAll()` — the
/// page-level "Reset this page" affordance added in AinkradAppKitContract.
/// These build minimal `SettingsField`s directly rather than going through a
/// real store, so the only thing under test is the filtering/invocation
/// logic itself.
@Suite("Settings page reset")
@MainActor
struct SettingsResetTests {
    /// A trivial mutable box so a field's `isModified`/`reset` closures can
    /// observe whether `reset` actually ran.
    final class Flag {
        var wasReset = false
    }

    private static func field(
        name: String, modified: Bool, resettable: Bool, flag: Flag
    ) -> SettingsField {
        SettingsField(
            path: SettingsPath(["test", name]),
            label: name,
            kind: .toggle(.constant(false)),
            defaultDescription: "Off",
            isModified: { modified },
            reset: resettable ? { flag.wasReset = true } : nil)
    }

    @Test("resetAll resets a modified, resettable field")
    func resetsModifiedResettableField() {
        let flag = Flag()
        let f = Self.field(name: "a", modified: true, resettable: true, flag: flag)
        let page = SettingsPage(
            path: SettingsPath(["test"]), title: "Test", icon: "gear",
            group: .workspace, order: 0,
            groups: [SettingsGroup(path: SettingsPath(["test", "group"]), title: "Group", fields: [f])])

        #expect(page.resettableFields.map(\.path) == [f.path])
        page.resetAll()
        #expect(flag.wasReset)
    }

    @Test("resetAll leaves an unmodified field alone even though it has a reset closure")
    func skipsUnmodifiedField() {
        let flag = Flag()
        let f = Self.field(name: "a", modified: false, resettable: true, flag: flag)
        let page = SettingsPage(
            path: SettingsPath(["test"]), title: "Test", icon: "gear",
            group: .workspace, order: 0,
            groups: [SettingsGroup(path: SettingsPath(["test", "group"]), title: "Group", fields: [f])])

        #expect(page.resettableFields.isEmpty)
        page.resetAll()
        #expect(!flag.wasReset)
    }

    @Test("resetAll skips a modified field with no reset closure instead of crashing")
    func skipsFieldWithNoReset() {
        let flag = Flag()
        let f = Self.field(name: "a", modified: true, resettable: false, flag: flag)
        let page = SettingsPage(
            path: SettingsPath(["test"]), title: "Test", icon: "gear",
            group: .workspace, order: 0,
            groups: [SettingsGroup(path: SettingsPath(["test", "group"]), title: "Group", fields: [f])])

        #expect(page.resettableFields.isEmpty)
        page.resetAll()  // must not crash
        #expect(!flag.wasReset)
    }

    @Test("resetAll only touches fields that are both modified and resettable, in a mixed page")
    func mixedPageResetsOnlyEligibleFields() {
        let flagA = Flag()
        let flagB = Flag()
        let flagC = Flag()
        let flagD = Flag()
        let modifiedResettable = Self.field(name: "a", modified: true, resettable: true, flag: flagA)
        let unmodifiedResettable = Self.field(name: "b", modified: false, resettable: true, flag: flagB)
        let modifiedNoReset = Self.field(name: "c", modified: true, resettable: false, flag: flagC)
        let unmodifiedNoReset = Self.field(name: "d", modified: false, resettable: false, flag: flagD)

        let page = SettingsPage(
            path: SettingsPath(["test"]), title: "Test", icon: "gear",
            group: .workspace, order: 0,
            groups: [
                SettingsGroup(
                    path: SettingsPath(["test", "group"]), title: "Group",
                    fields: [modifiedResettable, unmodifiedResettable, modifiedNoReset, unmodifiedNoReset])
            ])

        #expect(page.resettableFields.map(\.path) == [modifiedResettable.path])
        page.resetAll()
        #expect(flagA.wasReset)
        #expect(!flagB.wasReset)
        #expect(!flagC.wasReset)
        #expect(!flagD.wasReset)
    }
}
