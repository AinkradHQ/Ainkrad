import AinkradHostRuntime
import Observation

/// Owns the user's app-icon color + appearance settings: loads them from
/// `GlobalSettings`, persists changes (preserving other settings), and drives
/// the applier (using the current theme for Auto).
@MainActor
@Observable
final class AppIconStore {
    private(set) var choice: AppIconChoice
    private(set) var appearance: AppIconAppearance
    private let persistence: PersistenceStore
    private let applier: AppIconApplying
    private let themeManager: ThemeManager

    init(persistence: PersistenceStore, applier: AppIconApplying, themeManager: ThemeManager) {
        self.persistence = persistence
        self.applier = applier
        self.themeManager = themeManager
        let settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        self.choice = settings.appIconChoice
        self.appearance = settings.appIconAppearance
    }

    /// Apply the current settings to the running app (launch, theme change).
    func applyCurrent() {
        applier.apply(choice: choice, appearance: appearance, theme: themeManager.currentTheme)
    }

    func selectColor(_ choice: AppIconChoice) {
        self.choice = choice
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.appIconChoice = choice
        persistence.save(settings)
        applyCurrent()
    }

    func selectAppearance(_ appearance: AppIconAppearance) {
        self.appearance = appearance
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.appIconAppearance = appearance
        persistence.save(settings)
        applyCurrent()
    }
}
