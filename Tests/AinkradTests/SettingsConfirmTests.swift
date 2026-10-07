import AinkradAppKitContract
import AinkradAppKitUI
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// A destructive declared action no longer blocks on a modal `NSAlert`: it
/// leaves a request in `HostSettingsDrafts` for the overlay's
/// `AinkradConfirmDialog`, and the action runs only when that is confirmed.
@Suite("Settings destructive confirm")
@MainActor
struct SettingsConfirmTests {
    /// An environment holding one tool hook, and that hook's row.
    private func hookRow() throws -> (AppEnvironment, ToolHook, Binding<String>) {
        let environment = AppEnvironment.preview()
        let hook = try #require(ToolHookDraft(match: "edit_file", command: "echo hi").build())
        environment.toolHooksStore.add(hook)
        let field = try #require(
            HostSettingsCatalog.build(environment: environment).allFields.first {
                $0.path.segments.last == "hook-\(hook.id.uuidString)"
            })
        guard case .select(_, let selection) = field.kind else {
            Issue.record("the hook row is not a select row")
            throw CancellationError()
        }
        return (environment, hook, selection)
    }

    @Test("choosing Remove asks first and removes nothing yet")
    func removeAsksFirst() throws {
        let (environment, hook, selection) = try hookRow()
        selection.wrappedValue = "remove"

        let request = try #require(environment.settingsDrafts.pendingConfirm)
        #expect(request.title == "Remove this hook?")
        #expect(request.action == "Remove")
        #expect(environment.toolHooksStore.hooks.contains { $0.id == hook.id })
    }

    @Test("the action runs when the request is confirmed")
    func confirmRuns() throws {
        let (environment, hook, selection) = try hookRow()
        selection.wrappedValue = "remove"
        try #require(environment.settingsDrafts.pendingConfirm).onConfirm()
        #expect(!environment.toolHooksStore.hooks.contains { $0.id == hook.id })
    }

    @Test("a cancelled request never runs its action")
    func cancelDoesNothing() throws {
        let (environment, hook, selection) = try hookRow()
        selection.wrappedValue = "remove"
        // Cancel, Esc, the scrim and closing Settings all clear the request.
        environment.settingsDrafts.pendingConfirm = nil
        #expect(environment.toolHooksStore.hooks.contains { $0.id == hook.id })
    }

    @Test("the settings sidebar and confirm read the skin values they replaced")
    func skinValuesKeepToday() {
        for theme in Theme.allCases {
            let skin = ThemeCatalog.shared.themeFile(for: theme.rawValue).skin
            #expect(skin.chrome.overlay.backdropOpacity == 0.42)
            #expect(skin.motion.durations.d0_12 == 0.12)
            #expect(skin.size.s18 == 18 && skin.size.s52 == 52 && skin.size.s34 == 34)
            // The sidebar column; narrower truncates "Permissions & Sandbox".
            #expect(skin.size.s268 == 268)
        }
    }
}
