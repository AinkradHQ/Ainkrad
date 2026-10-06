#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — the gallery's own header and layout are showcase content
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// DEBUG-only design-system showcase: every SDK scale + component, rendered
/// across all 7 themes via a local theme switcher. Reachable from the
/// Launcher's "Component Gallery" system action (⌘K). Never compiled into a
/// release build — see `AppEnvironment.isComponentGalleryPresented` and
/// `LauncherView`'s `galleryRowID`.
///
/// The theme switcher drives its OWN `@State`, applied only to this view's
/// subtree via `.environment(\.ainkradTheme, …)` — switching it here never
/// touches `ThemeManager.currentTheme`, so the app's real theme (and every
/// other surface) is unaffected.
struct ComponentGalleryView: View {
    init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    let onDismiss: () -> Void
    @Environment(\.ainkradSkin) private var skin

    @State var galleryTheme: Theme = {
        parseDebugGalleryThemeArgument() ?? .neonBlue
    }()
    /// Drives the live Basic Shell sample — the Gallery is not a host pane, so
    /// it seeds the pane-mode environment itself.
    @State var galleryPaneMode: PluginMode = .basic
    @State var toggleOn = true
    @State var secureText = "sk-••••••••"
    @State var textFieldText = "Sample text"
    @State var sliderValue = 0.6
    @State var pickerSelection = 0
    @State var menuSelection = "Option A"
    @State var scanlineOn = true
    @State var hexGridOn = true
    @State var glowBloomOn = true
    @State var wave2ToggleOn = true
    @State var wave2Chips = ["Removable", "Draft"]

    // MARK: Wave 3: Inputs · Forms
    @State var wave3SelectSelection = "California"
    @State var wave3MultiSelectSelection: Set<String> = ["Option A"]
    @State var wave3ComboboxSelection: String?
    @State var wave3ComboboxText = ""
    @State var wave3SearchableSelectSelection = "Alabama"
    @State var wave3CheckboxOn = true
    @State var wave3RadioSelection = "Option A"
    @State var wave3StepperValue = 3
    @State var wave3RangeSliderValue: ClosedRange<Double> = 0.25...0.75
    @State var wave3SearchText = ""
    @State var wave3TextAreaText = "Sample multi-line text\nfor the text area."
    @State var wave3TextFieldText = "Sample text"
    @State var wave3SecureFieldText = "sk-••••••••"
    @State var wave3ToggleOn = true
    @State var wave3SegmentedSelection = 0
    @State var wave3SliderValue = 0.4

    // MARK: Wave 4: Navigation · Feedback
    @State var wave4TabsSelection = "Overview"
    @State var wave4PaginationPage = 0
    @State var wave4CommandMenuSelection: String?
    @State var wave4NavListSelection = "Dashboard"
    @State var wave4PopoverPresented = false
    @State var wave4ConfirmDialogPresented = false
    @State var wave4DestructiveConfirmDialogPresented = false

    // MARK: Wave 5: Data · Overlays
    @State var wave5TableSort: AinkradTableSort? = nil
    @State var wave5TableSelection: Set<String> = ["3"]
    @State var wave5Log = ComponentGalleryView.sampleLog()
    @State var wave5LogFollowing = true
    @State var wave5LogShowsSource = true
    @State var wave5ListRowSelection = "cpu-core-0"
    @State var wave5ModalPresented = false
    @State var wave5SheetPresented = false
    @State var wave5DrawerPresented = false

    var galleryTokens: HostThemeTokens { HostThemeTokens(from: galleryTheme) }
    var galleryStatusColors: AinkradStatusColors {
        AinkradStatusColors(
            success: galleryTheme.skin.color(\.success),
            warning: galleryTheme.skin.color(\.warning),
            danger: galleryTheme.skin.color(\.danger)
        )
    }
    var galleryTypography: AinkradTypography { .default }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                panel
                    .frame(
                        width: min(max(760, geo.size.width * 0.7), 980),
                        height: min(max(560, geo.size.height * 0.85), 780)
                    )
            }
        }
        // Local-only override — does NOT touch `environment.themeManager`.
        .environment(\.ainkradTheme, galleryTokens)
        .environment(\.ainkradStatusColors, galleryStatusColors)
        .environment(\.ainkradTypography, galleryTypography)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            themeSwitcher
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AinkradSpacing.xl) {
                        foundationSection.id("foundation")
                        scalesSection.id("scales")
                        panelSection.id("panel")
                        cardSection.id("card")
                        pickersSection.id("pickers")
                        formControlsSection.id("formControls")
                        stateViewsSection.id("stateViews")
                        sectionHeaderSection.id("sectionHeader")
                        wave2Section.id("wave2")
                        wave3Section.id("wave3")
                        wave4Section.id("wave4")
                        wave5Section.id("wave5")
                        themeFoundationSection.id("themeFoundation")
                    }
                    .padding(AinkradSpacing.lg)
                }
                .onAppear {
                    if let sectionID = parseDebugGallerySectionArgument() {
                        proxy.scrollTo(sectionID, anchor: .top)
                    }
                }
            }
        }
        .ainkradPanel()
        .ainkradToastHost()
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        // Attached at the gallery ROOT (the whole app surface), not a small
        // inner box — demonstrates `.ainkradConfirmDialog`'s documented
        // "attach at your app/surface root" usage: it dims and centers the
        // dialog within the entire gallery app, not just one control.
        .ainkradConfirmDialog(
            isPresented: $wave4ConfirmDialogPresented,
            title: "Confirm Action",
            message: "Are you sure you want to proceed?",
            onConfirm: {}
        )
        .ainkradConfirmDialog(
            isPresented: $wave4DestructiveConfirmDialogPresented,
            title: "Delete Item",
            message: "This action cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            onConfirm: {}
        )
        // Same "attach at the gallery ROOT" rationale as the confirm dialogs
        // above — `.ainkradModal`/`.ainkradSheet`/`.ainkradDrawer` dim and
        // scope to the entire gallery app surface, not a small inner box.
        .ainkradModal(isPresented: $wave5ModalPresented) {
            wave5OverlaySampleContent(
                title: "Modal Title",
                message: "Sample modal content, centered in the gallery app surface.",
                dismiss: { wave5ModalPresented = false }
            )
        }
        .ainkradSheet(isPresented: $wave5SheetPresented, edge: .bottom) {
            wave5OverlaySampleContent(
                title: "Sheet Title",
                message: "Sample sheet content, sliding up from the bottom edge.",
                dismiss: { wave5SheetPresented = false }
            )
        }
        .ainkradDrawer(isPresented: $wave5DrawerPresented, edge: .leading) {
            wave5OverlaySampleContent(
                title: "Drawer Title",
                message: "Sample drawer content, sliding in from the leading edge.",
                dismiss: { wave5DrawerPresented = false }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "swatchpalette")
                .foregroundStyle(galleryTokens.accentSecondary)
            Text("COMPONENT GALLERY")
                .font(AinkradFontResolver.font(.headline, weight: .semibold, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.9))
            Spacer()
            Text("esc")
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.4))
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .frame(height: 52)
    }

    private var themeSwitcher: some View {
        AinkradSegmentedPicker(items: Theme.allCases, selection: $galleryTheme) { $0.displayName }
            .padding(.horizontal, AinkradSpacing.lg)
            .padding(.bottom, AinkradSpacing.sm)
    }
}
#endif
