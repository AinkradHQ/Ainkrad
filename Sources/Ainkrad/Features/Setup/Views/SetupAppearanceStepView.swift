import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Applies the Appearance step's choices to the live stores.
///
/// Order is load-bearing: `setTheme` and `setColorScheme` clear `accentColorHex`,
/// so the accent must be set afterwards or it is lost.
@MainActor
enum SetupAppearance {
    static func apply(
        theme: String, colorScheme: String?, accentHex: String?,
        family: UIFontFamily, scale: UIFontScale,
        icon: AppIconChoice, iconAppearance: AppIconAppearance,
        themeManager: ThemeManager, iconStore: AppIconStore
    ) {
        themeManager.setTheme(theme)
        themeManager.setColorScheme(colorScheme, for: themeManager.appearance)
        themeManager.setAccentColorHex(accentHex)
        themeManager.setFontFamily(family)
        themeManager.setFontScale(scale)
        iconStore.selectColor(icon)
        iconStore.selectAppearance(iconAppearance)
    }
}

/// The Appearance step: theme, accent, typography and app-icon controls,
/// each applying immediately to the live `ThemeManager` / `AppIconStore`.
///
/// ART DIRECTION — the preview is the app, so the app is what is framed.
///
/// The workspace is loaded and rendering behind the blur; that is the entire
/// reason this wizard runs after bootstrap. The earlier pass at this screen
/// still spent it on swatches: four all-caps section headers, each control
/// under a form label ("FONT SIZE", "COLOR"), which reads as a settings pane
/// that happens to be live. Someone reading a labelled grid looks AT the grid.
///
/// So this version does three things instead:
///
/// 1. A lead line that points AWAY from the controls — the one sentence on the
///    screen whose job is to move the user's eye past it, to the window behind.
///    It names what is back there (islands, sky, chrome), because a person who
///    has never seen this app does not yet know what to watch.
/// 2. The controls carry prose, not labels. "Theme" with a sentence saying the
///    whole workspace re-tints, not "THEME" over a grid. Sentence case, said
///    the way a person would say it.
/// 3. The groups stage in, one after another, through `SetupStageMotion` — so
///    the screen assembles rather than landing as a form. Flat under
///    reduce-motion, which the user may have just turned on one step later (and
///    may return here with Back).
///
/// What did NOT change, deliberately: the controls themselves are still the
/// shared kit's, the same ones Settings uses for these preferences.
/// Art direction is framing and copy — inventing a wizard-only theme picker
/// would split one product into two visual languages for the same setting.
///
/// Controls that map onto a single store call (theme, font family/scale, icon
/// color/appearance) fire that setter directly. `SetupAppearance.apply` is not
/// used here: batching every control's current value through it on every change
/// would fight the "apply immediately, independently" model. It exists for the
/// *test* to pin the ordering trap on, not for the view to route through.
struct SetupAppearanceStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.setupGroupWidth) private var groupWidth
    @Environment(\.ainkradSkin) private var skin

    let coordinator: SetupCoordinator

    /// Flipped once on appear to stage the groups in. Never reset — coming Back
    /// to this step re-mounts the view.
    @State private var hasSettled = false

    var body: some View {
        let tokens = environment.themeManager.hostSkin

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    lead(tokens: tokens)
                    group(
                        index: 1,
                        title: "Theme",
                        hint: "The whole workspace re-tints — window, islands, and the sky "
                            + "behind this screen. Pick a theme, then its colours."
                    ) {
                        VStack(alignment: .leading, spacing: skin.size.s14) {
                            themeRow(tokens: tokens)
                            // A fresh install has only Neon; the rest are in the store.
                            AinkradButton(title: "More themes in the App Store", style: .ghost, icon: "paintbrush") {
                                environment.presentThemeStore()
                            }
                            themeGrid(tokens: tokens)
                        }
                    }
                    group(
                        index: 2,
                        title: "Accent",
                        hint: "Used for anything live: selection, focus, the things that are "
                            + "currently doing something."
                    ) {
                        accentColorRow(tokens: tokens, manager: environment.themeManager)
                    }
                    // "Type" first, which reads as a verb before it reads as a
                    // noun — an instruction to start typing, on a screen whose
                    // best line ("Look at the Dock") IS an instruction. Named
                    // for the two controls under it instead.
                    group(
                        index: 3,
                        title: "Typeface and size",
                        hint: "Every word in the app, including the ones you are reading now."
                    ) {
                        typographyControls(tokens: tokens)
                    }
                    group(
                        index: 4,
                        title: "App icon",
                        hint: "Look at the Dock — it changes as you pick."
                    ) {
                        appIconControls(tokens: tokens)
                    }
                }
                .padding(skin.size.s20)
                // FILLS the group, exactly as the Home step's folder listing
                // does. Capping the whole column instead left every panel hard
                // against the left edge with a void beside it — the layout read
                // as broken rather than as composed, because the empty space was
                // INSIDE the group rather than around it.
                //
                // Prose within the column is capped individually; see the
                // section hints.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { hasSettled = true }

            // Never blocking: every control here has a real default that is
            // already applied live, so there is nothing for the user to supply.
            SetupStepFooter(coordinator: coordinator) { coordinator.advance() }
        }
    }

    // MARK: - Lead

    /// The only sentence on this screen that is not attached to a control, and
    /// the only one that matters if the user reads nothing else: it says the
    /// thing behind the blur is the real app, already running.
    private func lead(tokens: AinkradSkin) -> some View {
        staged(index: 0) {
            Text(
                "Ainkrad is already running behind this screen — that is your workspace "
                    + "back there, not a picture of one. Nothing here needs saving: change "
                    + "something and watch it happen."
            )
            .font(AinkradFont.display(15))
            .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o85))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Theme

    private var choiceColumns: [GridItem] {
        [GridItem(.adaptive(minimum: skin.size.s200, maximum: skin.size.s260), spacing: skin.size.s10)]
    }

    /// One card per installed theme (design language).
    // ponytail: every theme card shows the current skin's accents; a per-theme preview is E5.6.
    private func themeRow(tokens: AinkradSkin) -> some View {
        let manager = environment.themeManager
        return LazyVGrid(columns: choiceColumns, spacing: skin.size.s10) {
            ForEach(manager.themes, id: \.id) { theme in
                choiceCard(
                    theme.name, isSelected: manager.activeThemeID == theme.id, swatch: manager.skin,
                    tokens: tokens, onTap: { manager.setTheme(theme.id) })
            }
        }
    }

    /// One card per colour scheme of the current appearance.
    private func themeGrid(tokens: AinkradSkin) -> some View {
        let manager = environment.themeManager
        return LazyVGrid(columns: choiceColumns, spacing: skin.size.s10) {
            ForEach(manager.colorSchemes, id: \.id) { scheme in
                choiceCard(
                    scheme.name, isSelected: manager.skin.id == scheme.id,
                    swatch: manager.skin(forScheme: scheme.id) ?? manager.skin, tokens: tokens,
                    onTap: { manager.setColorScheme(scheme.id, for: manager.appearance) })
            }
        }
    }

    /// A kit list row: the swatch skin's two accents as the leading chip, and
    /// a tick that reads as the current choice.
    private func choiceCard(
        _ title: String, isSelected: Bool, swatch themeSkin: AinkradSkin, tokens: AinkradSkin,
        onTap: @escaping () -> Void
    ) -> some View {
        AinkradListRow(
            isSelected: isSelected,
            onTap: onTap,
            leading: {
                ChamferShape(cut: skin.cut.c7)
                    .fill(
                        LinearGradient(
                            colors: [themeSkin.color(\.accentPrimary), themeSkin.color(\.accentSecondary)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: skin.size.s30, height: skin.size.s30)
                    .overlay(
                        ChamferShape(cut: skin.cut.c7)
                            .strokeBorder(skin.color(.palette("white", skin.opacity.o18)), lineWidth: 1)
                    )
            },
            title: title,
            trailing: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(skin.font(AinkradFontToken(sizeKey: "t13", scaled: false)))
                    .foregroundStyle(isSelected ? tokens.color(\.accentSecondary) : tokens.color(\.foreground).opacity(skin.opacity.o25))
            }
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Accent

    /// Preset swatches (one per theme's accent) plus a color-well for
    /// anything else — the same color well Settings' accent row uses, so the
    /// wizard and Settings agree on how an accent is picked. A well over a
    /// palette-only picker is required here because the accent is a
    /// free-form 6-digit hex, not one of a fixed set — restricting the
    /// wizard to presets while Settings allows any color would be a
    /// regression the moment the user opens Settings afterward.
    private func accentColorRow(tokens: AinkradSkin, manager: ThemeManager) -> some View {
        HStack(spacing: skin.size.s9) {
            ForEach(manager.colorSchemes, id: \.id) { scheme in
                accentSwatch(scheme, tokens: tokens, manager: manager)
            }
            AinkradColorPicker(
                selection: Binding(
                    get: { manager.hostSkin.color(\.accentPrimary) },
                    set: { manager.setAccentColor($0) }
                )
            )
            .frame(width: skin.size.s30, height: skin.size.s30)
            .help("Any other colour")
            .accessibilityLabel("Choose any other accent colour")
        }
    }

    /// One accent preset.
    ///
    /// Chamfered rather than round, to match the theme cards above it — the two
    /// rows were a grid of chamfers over a row of circles, which read as two
    /// unrelated controls rather than as one screen.
    ///
    /// The selected state also accounts for INHERITANCE. `accentColorHex` is nil
    /// until the user picks an accent explicitly, and the old check keyed only
    /// off that — so on arrival nothing was selected at all, even though the
    /// workspace visibly had an accent. It now shows the theme's own accent as
    /// the current one, which is what the user is actually looking at.
    private func accentSwatch(
        _ scheme: ThemeColorScheme, tokens: AinkradSkin,
        manager: ThemeManager
    ) -> some View {
        let color = (manager.skin(forScheme: scheme.id) ?? manager.skin).color(\.accentPrimary)
        let hex = color.hexString ?? ""
        let isSelected = AccentSelection.isSelected(
            swatchHex: hex,
            overrideHex: manager.accentColorHex,
            themeAccentHex: manager.skin.color(\.accentPrimary).hexString ?? "")

        // A raw `Button`: the kit's swatch chip carries a text label, and seven
        // labelled chips plus the well cannot fit the row a 280pt column gives.
        return Button {  // design-lint: allow raw-control kit gap, label-free colour swatch
            manager.setAccentColorHex(hex)
        } label: {
            ChamferShape(cut: skin.cut.c7)
                .fill(color)
                .frame(width: skin.size.s30, height: skin.size.s30)
                .overlay(
                    ChamferShape(cut: skin.cut.c7).strokeBorder(
                        isSelected
                            ? tokens.color(\.foreground).opacity(skin.opacity.o95)
                            : skin.color(.palette("white", skin.opacity.o16)),
                        lineWidth: isSelected ? 2 : 1
                    )
                )
                .overlay(
                    // A tick, not just a ring: at 30pt a 2pt ring alone is easy
                    // to miss, and this control has no other confirmation.
                    Image(systemName: "checkmark")
                        .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "bold", scaled: false)))
                        .foregroundStyle(skin.color(.palette("white", 1)))
                        .shadow(color: skin.color(.palette("black", skin.opacity.o40)), radius: skin.size.s2)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(scheme.name)
        .accessibilityLabel("\(scheme.name) accent")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Typography

    private func typographyControls(tokens: AinkradSkin) -> some View {
        let manager = environment.themeManager
        return VStack(alignment: .leading, spacing: skin.size.s9) {
            AinkradCaptionedRow("Typeface") {
                AinkradSegmentedPicker(
                    items: UIFontFamily.allCases,
                    selection: Binding(
                        get: { manager.uiFontFamily },
                        set: { manager.setFontFamily($0) }),
                    label: fontFamilyTitle
                )
            }
            AinkradCaptionedRow("Size") {
                AinkradSegmentedPicker(
                    items: UIFontScale.allCases,
                    selection: Binding(
                        get: { manager.uiFontScale },
                        set: { manager.setFontScale($0) }),
                    label: fontScaleTitle
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font family and size")
    }

    // MARK: - App icon

    private func appIconControls(tokens: AinkradSkin) -> some View {
        let store = environment.appIconStore
        return VStack(alignment: .leading, spacing: skin.size.s9) {
            AinkradCaptionedRow(AppIconCaptions.color) {
                AinkradSegmentedPicker(
                    items: AppIconChoice.allCases,
                    selection: Binding(get: { store.choice }, set: { store.selectColor($0) }),
                    label: iconColorTitle
                )
            }
            AinkradCaptionedRow(AppIconCaptions.appearance) {
                AinkradSegmentedPicker(
                    items: AppIconAppearance.allCases,
                    selection: Binding(
                        get: { store.appearance },
                        set: { store.selectAppearance($0) }),
                    label: iconAppearanceTitle
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App icon color and appearance")
    }

    // MARK: - Group + staging

    /// One choice: a spoken title, a sentence saying what the user will see
    /// change, and the control. No all-caps header, no boxed card and no rule
    /// above it — the groups are separated by space alone, per the design
    /// language's no-separator rule.
    private func group<Content: View>(
        index: Int, title: String, hint: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        staged(index: index) {
            AinkradSettingsPanel(title: title, hint: hint, content: content)
        }
    }

    /// The staging itself, routed through `SetupStageMotion` — never a bare
    /// `.animation(...)`. Under reduce-motion `layerGeometry` returns `nil` and
    /// `animation` returns `nil`, so there is no lift, no stagger and nothing
    /// to fade from: the group is simply present.
    ///
    /// `isForward: true` is not a direction claim — the stage already owns
    /// directional entry for the step as a whole. It is asked in the forward
    /// orientation purely to take the magnitude and the reduce-motion gate,
    /// the same way `SetupHomeStepView` does for its folder rows.
    private func staged<Content: View>(
        index: Int,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let geometry = SetupStageMotion.layerGeometry(
            .content,
            reduceMotion: reduceMotion,
            isForward: true)
        let lift = geometry.map { $0.lift * 0.6 } ?? 0
        // ONLY the per-index stagger — `SetupStageMotion.animation(layer:)`
        // already carries `.content`'s own 0.11s delay, and adding
        // `geometry.delay` to it double-counted, holding the first group off
        // screen for 0.22s. `geometry` is still consulted because `nil` is the
        // reduce-motion seam.
        let delay = geometry.map { _ in Double(index) * 0.06 } ?? 0

        return content()
            .opacity(hasSettled ? 1 : 0)
            .offset(y: hasSettled ? 0 : lift)
            .animation(
                SetupStageMotion.animation(
                    reduceMotion: reduceMotion,
                    layer: .content)?.delay(delay),
                value: hasSettled)
    }

    // MARK: - Titles

    private func fontScaleTitle(_ scale: UIFontScale) -> String {
        switch scale {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    private func fontFamilyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    private func iconColorTitle(_ c: AppIconChoice) -> String {
        switch c {
        case .auto: return "Auto"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    private func iconAppearanceTitle(_ a: AppIconAppearance) -> String {
        switch a {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
