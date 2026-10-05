import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// Resolves the typography Hoard renders with: its own per-app override if the
/// user set one, otherwise the global Appearance setting.
///
/// The first cut hardcoded `.system(size: 12.5)` throughout, which ignored both
/// the workspace font and the per-app override entirely — the app looked like a
/// foreign surface rather than part of Ainkrad. Everything in Hoard now reads
/// `\.ainkradTypography` and sizes through `AinkradFontResolver`, so a change
/// to either setting flows through live.
@MainActor
enum HoardTypography {
    static func resolve(appEnvironment: AppEnvironment) -> AinkradTypography {
        let appearance = appEnvironment.appAppearanceStore
        let manager = appEnvironment.themeManager
        let family = appearance.fontFamily(HoardApp.id) ?? manager.uiFontFamily
        let scale = appearance.fontScale(HoardApp.id) ?? manager.uiFontScale
        return AinkradTypography(fontFamilyName: family.fontName, scale: scale.multiplier)
    }
}

extension View {
    /// Applies Hoard' resolved typography to a subtree.
    ///
    /// The parameter is `appEnvironment`, not `environment`: naming it
    /// `environment` shadows SwiftUI's own `environment(_:_:)` modifier inside
    /// this scope, and the call below then fails to resolve.
    @MainActor
    func filesTypography(_ appEnvironment: AppEnvironment) -> some View {
        self.environment(
            \.ainkradTypography,
            HoardTypography.resolve(appEnvironment: appEnvironment))
    }
}
