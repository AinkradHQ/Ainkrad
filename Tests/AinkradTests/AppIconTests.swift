import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

struct ThemeIconFamilyTests {
    @Test("every theme maps to its locked icon color family")
    func families() {
        #expect(Theme.neonBlue.iconColorFamily      == .blue)
        #expect(Theme.cyberPurple.iconColorFamily   == .purple)
        #expect(Theme.dracula.iconColorFamily       == .purple)
        #expect(Theme.nord.iconColorFamily          == .blue)
        #expect(Theme.tokyoNight.iconColorFamily    == .blue)
        #expect(Theme.gruvbox.iconColorFamily       == .blue)
        #expect(Theme.solarizedDark.iconColorFamily == .blue)
    }
}

struct AppIconResolverTests {
    @Test("color resolves auto→theme family, else the explicit color")
    func color() {
        #expect(AppIconResolver.color(for: .auto, theme: .cyberPurple) == .purple)
        #expect(AppIconResolver.color(for: .auto, theme: .neonBlue)    == .blue)
        #expect(AppIconResolver.color(for: .blue, theme: .cyberPurple) == .blue)
        #expect(AppIconResolver.color(for: .purple, theme: .neonBlue)  == .purple)
    }

    @Test("isDark: system passes through, light/dark pin")
    func isDark() {
        #expect(AppIconResolver.isDark(.system, systemDark: true)  == true)
        #expect(AppIconResolver.isDark(.system, systemDark: false) == false)
        #expect(AppIconResolver.isDark(.light, systemDark: true)   == false)
        #expect(AppIconResolver.isDark(.dark,  systemDark: false)  == true)
    }

    @Test("resourceName composes color + appearance into the bundled name")
    func resourceName() {
        #expect(AppIconResolver.resourceName(for: .auto, theme: .cyberPurple, appearance: .system, systemDark: true) == "purple-dark")
        #expect(AppIconResolver.resourceName(for: .auto, theme: .neonBlue, appearance: .light, systemDark: true) == "blue-light")
        #expect(AppIconResolver.resourceName(for: .blue, theme: .dracula, appearance: .dark, systemDark: false) == "blue-dark")
        #expect(AppIconResolver.resourceName(for: .purple, theme: .neonBlue, appearance: .system, systemDark: false) == "purple-light")
    }

    @Test("every (choice,appearance) resolves to a bundled .icns")
    func allBundled() {
        for choice in AppIconChoice.allCases {
            for appearance in AppIconAppearance.allCases {
                for dark in [true, false] {
                    let name = AppIconResolver.resourceName(for: choice, theme: .neonBlue, appearance: appearance, systemDark: dark)
                    #expect(Bundle.main.url(forResource: name, withExtension: "icns") != nil, "missing \(name).icns")
                }
            }
        }
    }
}

struct GlobalSettingsAppIconTests {
    @Test("fresh defaults: color auto, appearance system")
    func defaults() {
        let s = GlobalSettings()
        #expect(s.appIconChoice == .auto)
        #expect(s.appIconAppearance == .system)
    }

    @Test("round-trips both fields")
    func roundTrip() throws {
        var s = GlobalSettings()
        s.appIconChoice = .purple
        s.appIconAppearance = .dark
        let back = try JSONDecoder().decode(GlobalSettings.self, from: try JSONEncoder().encode(s))
        #expect(back.appIconChoice == .purple)
        #expect(back.appIconAppearance == .dark)
    }

    @Test("a v1 doc (appIconChoice only) decodes: choice preserved, appearance defaults to system")
    func legacyV1Decodes() throws {
        let legacy = Data(#"{"theme":"neonBlue","appIconChoice":"blue"}"#.utf8)
        let s = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(s.appIconChoice == .blue)
        #expect(s.appIconAppearance == .system)
    }
}

@MainActor
private final class FakeApplier: AppIconApplying {
    private(set) var calls: [(choice: AppIconChoice, appearance: AppIconAppearance, theme: Theme)] = []
    func apply(choice: AppIconChoice, appearance: AppIconAppearance, theme: Theme) {
        calls.append((choice, appearance, theme))
    }
}

@MainActor
struct AppIconStoreTests {
    private func makeThemeManager(_ p: PersistenceStore) -> ThemeManager { ThemeManager(persistence: p) }

    @Test("loads persisted color + appearance")
    func loads() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .neonBlue, appIconChoice: .purple, appIconAppearance: .dark))
        let store = AppIconStore(persistence: p, applier: FakeApplier(), themeManager: makeThemeManager(p))
        #expect(store.choice == .purple)
        #expect(store.appearance == .dark)
    }

    @Test("selectColor persists color (preserving theme + appearance) and applies")
    func selectColor() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .dracula, appIconChoice: .auto, appIconAppearance: .light))
        let applier = FakeApplier()
        let tm = makeThemeManager(p)
        let store = AppIconStore(persistence: p, applier: applier, themeManager: tm)
        store.selectColor(.blue)
        #expect(store.choice == .blue)
        let saved = p.load(GlobalSettings.self)
        #expect(saved?.appIconChoice == .blue)
        #expect(saved?.appIconAppearance == .light)   // preserved
        #expect(saved?.theme == .dracula)             // preserved
        #expect(applier.calls.last?.choice == .blue)
        #expect(applier.calls.last?.appearance == .light)
        #expect(applier.calls.last?.theme == .dracula)
    }

    @Test("selectAppearance persists appearance (preserving theme + color) and applies")
    func selectAppearance() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .nord, appIconChoice: .purple, appIconAppearance: .system))
        let applier = FakeApplier()
        let store = AppIconStore(persistence: p, applier: applier, themeManager: makeThemeManager(p))
        store.selectAppearance(.dark)
        #expect(store.appearance == .dark)
        let saved = p.load(GlobalSettings.self)
        #expect(saved?.appIconAppearance == .dark)
        #expect(saved?.appIconChoice == .purple)      // preserved
        #expect(saved?.theme == .nord)                // preserved
        #expect(applier.calls.last?.appearance == .dark)
    }

    @Test("applyCurrent applies loaded values with the current theme")
    func applyCurrent() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .cyberPurple, appIconChoice: .auto, appIconAppearance: .system))
        let applier = FakeApplier()
        let store = AppIconStore(persistence: p, applier: applier, themeManager: makeThemeManager(p))
        store.applyCurrent()
        #expect(applier.calls.last?.choice == .auto)
        #expect(applier.calls.last?.theme == .cyberPurple)
    }

    @Test("theme change re-applies with the new theme")
    func themeChangeReapplies() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .neonBlue, appIconChoice: .auto, appIconAppearance: .system))
        let applier = FakeApplier()
        let tm = makeThemeManager(p)
        let store = AppIconStore(persistence: p, applier: applier, themeManager: tm)
        tm.onThemeChange = { [weak store] in store?.applyCurrent() }   // wired as bootstrap does
        tm.setTheme(.cyberPurple)
        #expect(applier.calls.last?.theme == .cyberPurple)
    }
}

@Suite("Bundle icon stamping")
struct BundleAppIconTests {
    @Test("stamps when the resolved icon differs from what is on the bundle")
    func stampsOnChange() {
        #expect(BundleAppIcon.decide(resolved: "purple-dark", lastWritten: nil,
                                     matchesShippedIcon: false) == .write("purple-dark"))
        #expect(BundleAppIcon.decide(resolved: "purple-dark", lastWritten: "blue-light",
                                     matchesShippedIcon: false) == .write("purple-dark"))
    }

    @Test("does nothing when the bundle already carries the resolved icon")
    func noopWhenUnchanged() {
        #expect(BundleAppIcon.decide(resolved: "purple-dark", lastWritten: "purple-dark",
                                     matchesShippedIcon: false) == .none)
    }

    @Test("never stamps when the shipped icon is already the right one")
    func noStampWhenShippedIconMatches() {
        #expect(BundleAppIcon.decide(resolved: "blue-dark", lastWritten: nil,
                                     matchesShippedIcon: true) == .none)
    }

    @Test("clears an existing stamp once the shipped icon becomes correct")
    func clearsStampWhenShippedIconMatches() {
        #expect(BundleAppIcon.decide(resolved: "blue-dark", lastWritten: "purple-dark",
                                     matchesShippedIcon: true) == .clear)
        // Already clean — clearing again would be a pointless bundle write.
        #expect(BundleAppIcon.decide(resolved: "blue-dark", lastWritten: nil,
                                     matchesShippedIcon: true) == .none)
    }
}
