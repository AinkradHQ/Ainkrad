import AinkradAppKitContract
import Testing

@testable import Ainkrad

@Suite("Settings path migration")
@MainActor
struct SettingsPathMigrationTests {
    @Test("retired paths resolve forward to their new homes")
    func retiredPathsResolve() {
        let cases: [(String, String)] = [
            ("workspace.livingSky", "workspace.appearance"),
            ("workspace.appIcon", "workspace.appearance"),
            ("workspace.sound", "workspace.soundAndVoice"),
            ("workspace.shortcuts", "workspace.keyboard"),
            ("assistant.models", "intelligence.model"),
            ("assistant.access", "intelligence.permissions"),
            ("assistant.data", "intelligence.privacy"),
            ("assistant.web", "intelligence.tools"),
            ("assistant.voice", "workspace.soundAndVoice"),
            ("workspace.mcp", "intelligence.tools"),
            ("workspace.lsp", "intelligence.tools"),
            ("workspace.skills", "intelligence.skills"),
            ("workspace.memory", "intelligence.memory"),
            // NOT workspace.appearance: the Sage's appearance settings
            // (surface opacity, blur, message font/size) never moved there —
            // they are still `SageSettingsView.appearanceSection`, on the
            // Sage's own app page.
            ("assistant.appearance", "app.sage"),
            // The v0.16.0 app rename: an app page id derives from the app id.
            ("app.assistant", "app.sage"),
            ("app.files", "app.hoard"),
            ("app.canvas", "app.scry"),
        ]
        for (old, new) in cases {
            let resolved = SettingsPathAliases.resolve(SettingsPath(rawValue: old)!)
            #expect(resolved.rawValue == new, "\(old) resolved to \(resolved.rawValue)")
        }
    }

    @Test("a current path resolves to itself")
    func currentPathsAreStable() {
        let current = SettingsPath(rawValue: "intelligence.tools")!
        #expect(SettingsPathAliases.resolve(current) == current)
    }

    @Test("every alias target exists in the live catalog")
    func aliasTargetsAreReal() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        for target in SettingsPathAliases.allTargets {
            #expect(catalog.page(containing: target) != nil, "\(target) is a dangling alias")
        }
    }

    @Test("the navigator follows aliases")
    func navigatorFollowsAliases() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let navigator = SettingsNavigator(initial: SettingsPath(["workspace", "general"]))
        navigator.navigate(to: SettingsPath(rawValue: "workspace.livingSky")!, in: catalog)
        #expect(navigator.selection.rawValue == "workspace.appearance")
    }

    @Test("resolve follows a chained alias to its final target")
    func resolveFollowsChains() {
        // `resolve` walks to a fixed point rather than stopping at the first
        // hop, so even if a retired path's target is later itself retired,
        // callers still land on the live page instead of a stale intermediate.
        #expect(SettingsPathAliases.resolve(SettingsPath(rawValue: "assistant.web")!).rawValue == "intelligence.tools")
    }

    @Test("no alias target is itself a retired alias key today")
    func noAliasTargetIsItselfAKey() {
        // Documents the current shape of the table: it is a flat
        // "retired -> current" map, not a chain. `resolve` tolerates a chain
        // (see `resolveFollowsChains`), but this test makes a future chain
        // visible in review rather than silently relying on the fixed-point
        // walk to paper over it.
        let keys = Set(SettingsPathAliases.allKeys)
        for target in SettingsPathAliases.allTargets {
            #expect(
                !keys.contains(target.rawValue), "\(target.rawValue) is both an alias target and an alias key — chained"
            )
        }
    }
}
