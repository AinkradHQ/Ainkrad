#if DEBUG
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
    let onDismiss: () -> Void

    @State private var galleryTheme: Theme = .neonBlue
    @State private var toggleOn = true
    @State private var secureText = "sk-••••••••"
    @State private var textFieldText = "Sample text"
    @State private var sliderValue = 0.6
    @State private var pickerSelection = 0
    @State private var menuSelection = "Option A"
    @State private var scanlineOn = true
    @State private var hexGridOn = true
    @State private var glowBloomOn = true
    @State private var wave2ToggleOn = true
    @State private var wave2Chips = ["Removable", "Draft"]

    // MARK: Wave 3: Inputs · Forms
    @State private var wave3SelectSelection = "California"
    @State private var wave3MultiSelectSelection: Set<String> = ["Option A"]
    @State private var wave3ComboboxSelection: String?
    @State private var wave3ComboboxText = ""
    @State private var wave3SearchableSelectSelection = "Alabama"
    @State private var wave3CheckboxOn = true
    @State private var wave3RadioSelection = "Option A"
    @State private var wave3StepperValue = 3
    @State private var wave3RangeSliderValue: ClosedRange<Double> = 0.25...0.75
    @State private var wave3SearchText = ""
    @State private var wave3TextAreaText = "Sample multi-line text\nfor the text area."
    @State private var wave3TextFieldText = "Sample text"
    @State private var wave3SecureFieldText = "sk-••••••••"
    @State private var wave3ToggleOn = true
    @State private var wave3SegmentedSelection = 0
    @State private var wave3SliderValue = 0.4

    // MARK: Wave 4: Navigation · Feedback
    @State private var wave4TabsSelection = "Overview"
    @State private var wave4PaginationPage = 0
    @State private var wave4CommandMenuSelection: String?
    @State private var wave4NavListSelection = "Dashboard"
    @State private var wave4PopoverPresented = false
    @State private var wave4ConfirmDialogPresented = false
    @State private var wave4DestructiveConfirmDialogPresented = false

    // MARK: Wave 5: Data · Overlays
    @State private var wave5TableSort: AinkradTableSort? = nil
    @State private var wave5TableSelection: Set<String> = ["3"]
    @State private var wave5Log = ComponentGalleryView.sampleLog()
    @State private var wave5LogFollowing = true
    @State private var wave5LogShowsSource = true
    @State private var wave5ListRowSelection = "cpu-core-0"
    @State private var wave5ModalPresented = false
    @State private var wave5SheetPresented = false
    @State private var wave5DrawerPresented = false

    private var galleryTokens: HostThemeTokens { HostThemeTokens(from: galleryTheme) }
    private var galleryStatusColors: AinkradStatusColors {
        AinkradStatusColors(
            success: galleryTheme.tokens.success,
            warning: galleryTheme.tokens.warning,
            danger: galleryTheme.tokens.danger
        )
    }
    private var galleryTypography: AinkradTypography { .default }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
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
            ScrollView {
                VStack(alignment: .leading, spacing: AinkradSpacing.xl) {
                    foundationSection
                    scalesSection
                    panelSection
                    cardSection
                    pickersSection
                    formControlsSection
                    stateViewsSection
                    sectionHeaderSection
                    wave2Section
                    wave3Section
                    wave4Section
                    wave5Section
                }
                .padding(AinkradSpacing.lg)
            }
        }
        .ainkradPanel()
        .ainkradToastHost()
        .onKeyPress(.escape) { onDismiss(); return .handled }
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

    private func wave5OverlaySampleContent(title: String, message: String, dismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            Text(title)
                .font(AinkradFontResolver.font(.headline, weight: .semibold, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground)
            Text(message)
                .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.8))
            AinkradButton(title: "Close", style: .secondary, action: dismiss)
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

    // MARK: - Sections

    private var foundationSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Foundation", subtitle: "Chamfer, brackets, accent rule, effects, status colors")

            HStack(spacing: AinkradSpacing.md) {
                ChamferShape()
                    .fill(galleryTokens.surfaceElevated)
                    .frame(width: 120, height: 80)
                    .cornerBrackets()
            }

            AccentRule(label: "Accent Rule")

            HStack(spacing: AinkradSpacing.md) {
                VStack(spacing: 4) {
                    effectSamplePanel.scanlineOverlay(active: scanlineOn)
                    AinkradCheckbox(isOn: $scanlineOn, label: "Scanline")
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }

                VStack(spacing: 4) {
                    effectSamplePanel.hexGridBackground(active: hexGridOn)
                    AinkradCheckbox(isOn: $hexGridOn, label: "Hex Grid")
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }

                VStack(spacing: 4) {
                    effectSamplePanel.glowBloom(active: glowBloomOn)
                    AinkradCheckbox(isOn: $glowBloomOn, label: "Glow Bloom")
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }
            }

            HStack(spacing: AinkradSpacing.lg) {
                statusSwatch(label: "Success", color: galleryTheme.tokens.success)
                statusSwatch(label: "Warning", color: galleryTheme.tokens.warning)
                statusSwatch(label: "Danger", color: galleryTheme.tokens.danger)
            }
            .padding(.top, AinkradSpacing.sm)
        }
    }

    private var effectSamplePanel: some View {
        RoundedRectangle(cornerRadius: AinkradRadius.sm)
            .fill(galleryTokens.surface)
            .frame(width: 96, height: 64)
    }

    private func statusSwatch(label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AinkradRadius.sm)
                .fill(color)
                .frame(width: 64, height: 32)
            Text(label)
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.6))
        }
    }

    private var scalesSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Scales", subtitle: "Spacing, radius, elevation, type roles")

            HStack(spacing: AinkradSpacing.sm) {
                ForEach(spacingSamples, id: \.label) { sample in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(galleryTokens.accentPrimary.opacity(0.6))
                            .frame(width: sample.value, height: 12)
                        Text(sample.label)
                            .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                            .foregroundStyle(galleryTokens.foreground.opacity(0.6))
                    }
                }
            }

            HStack(spacing: AinkradSpacing.md) {
                ForEach(radiusSamples, id: \.label) { sample in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: sample.value)
                            .fill(galleryTokens.surfaceElevated)
                            .frame(width: 48, height: 32)
                        Text(sample.label)
                            .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                            .foregroundStyle(galleryTokens.foreground.opacity(0.6))
                    }
                }
            }

            HStack(spacing: AinkradSpacing.lg) {
                elevationSample(label: "level0", shadow: AinkradElevation.level0)
                elevationSample(label: "level1", shadow: AinkradElevation.level1)
                elevationSample(label: "level2", shadow: AinkradElevation.level2)
            }
            .padding(.top, AinkradSpacing.sm)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AinkradTypeRole.allCases, id: \.self) { role in
                    Text("\(String(describing: role)) — \(Int(role.size))pt")
                        .font(AinkradFontResolver.font(role, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground)
                }
            }
            .padding(.top, AinkradSpacing.sm)
        }
    }

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Panel")
            AinkradPanel {
                Text("AinkradPanel content")
                    .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                    .foregroundStyle(galleryTokens.foreground)
                    .padding(AinkradSpacing.lg)
            }
            .frame(height: 80)
        }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Card", subtitle: "Default, hover-capable, selected")
            HStack(spacing: AinkradSpacing.md) {
                AinkradCard {
                    cardLabel("Default")
                }
                AinkradCard(onTap: {}) {
                    cardLabel("Interactive")
                }
                AinkradCard(isSelected: true) {
                    cardLabel("Selected")
                }
            }
        }
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(AinkradFontResolver.font(.body, typography: galleryTypography))
            .foregroundStyle(galleryTokens.foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var pickersSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Pickers")
            AinkradSegmentedPicker(items: Array(0..<3), selection: $pickerSelection) { "Item \($0)" }
            AinkradSelect(items: ["Option A", "Option B", "Option C"], selection: $menuSelection) { $0 }
        }
    }

    private var formControlsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Form Controls")
            AinkradFormRow(title: "Enable feature", help: "A toggle in a form row") {
                AinkradToggle(isOn: $toggleOn)
            }
            AinkradTextField(text: $textFieldText, placeholder: "Text field")
            AinkradSecureField(text: $secureText, placeholder: "Secure field")
            AinkradSlider(value: $sliderValue, in: 0...1)
        }
    }

    private var stateViewsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "State Views")
            HStack(spacing: AinkradSpacing.md) {
                AinkradEmptyState(icon: "tray", title: "Nothing here", message: "No items yet.",
                                  actionTitle: "Add Item", action: {})
                    .frame(height: 180)
                AinkradLoadingState(label: "Loading…")
                    .frame(height: 180)
                AinkradErrorState(message: "Something went wrong.", retryTitle: "Retry", retry: {})
                    .frame(height: 180)
            }
        }
    }

    private var sectionHeaderSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Section Header", subtitle: "Uppercased caption label, no separator line")
        }
    }

    // MARK: - Wave 2: Surfaces · Buttons · Type

    private var wave2Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Surfaces · Buttons · Type", subtitle: "Wave-2 Cardinal HUD components")

            wave2SurfacesRow
            wave2SectionFrameSample
            wave2ButtonsRow
            wave2TagsRow
            wave2TypeRow
        }
    }

    private var wave2SurfacesRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Panel (default / bracketed) & Card (default / interactive / selected)")
            HStack(alignment: .top, spacing: AinkradSpacing.md) {
                AinkradPanel {
                    wave2SampleText("Panel")
                        .padding(AinkradSpacing.lg)
                }
                .frame(width: 140, height: 80)

                AinkradPanel(showsBrackets: true) {
                    wave2SampleText("Panel + brackets")
                        .padding(AinkradSpacing.lg)
                }
                .frame(width: 140, height: 80)

                AinkradCard {
                    wave2SampleText("Default")
                }
                AinkradCard(onTap: {}) {
                    wave2SampleText("Hover-capable")
                }
                AinkradCard(isSelected: true) {
                    wave2SampleText("Selected")
                }
            }
        }
    }

    private func wave2SampleText(_ text: String) -> some View {
        Text(text)
            .font(AinkradFontResolver.font(.body, typography: galleryTypography))
            .foregroundStyle(galleryTokens.foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var wave2SectionFrameSample: some View {
        AinkradSectionFrame(title: "Section Frame") {
            AinkradLabel("Framed content sample", systemName: "square.stack.3d.up")
        }
    }

    private var wave2ButtonsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Buttons — all 4 styles, icon button, toggle button")
            HStack(spacing: AinkradSpacing.md) {
                AinkradButton(title: "Primary", style: .primary, action: {})
                AinkradButton(title: "Secondary", style: .secondary, action: {})
                AinkradButton(title: "Ghost", style: .ghost, action: {})
                AinkradButton(title: "Danger", style: .danger, action: {})
                AinkradIconButton(systemName: "bolt.fill", action: {})
                AinkradToggleButton(isOn: $wave2ToggleOn, systemName: "power", title: "Latch")
            }
        }
    }

    private var wave2TagsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Chips, badges (all statuses), keyboard shortcuts")
            HStack(spacing: AinkradSpacing.md) {
                ForEach(wave2Chips, id: \.self) { chip in
                    AinkradChip(label: chip, systemName: "tag", onRemove: {
                        wave2Chips.removeAll { $0 == chip }
                    })
                }
                AinkradChip(label: "Static")
            }
            HStack(spacing: AinkradSpacing.sm) {
                ForEach(AinkradStatus.allCases, id: \.self) { status in
                    AinkradBadge(text: String(describing: status), status: status)
                }
            }
            HStack(spacing: AinkradSpacing.xs) {
                AinkradKbd("⌘")
                AinkradKbd("⇧")
                AinkradKbd("K")
            }
        }
    }

    private var wave2TypeRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Label & Caption")
            AinkradLabel("Sample label text", systemName: "text.alignleft")
            AinkradCaption("Sample dimmed caption text")
        }
    }

    // MARK: - Wave 3: Inputs · Forms

    private var wave3Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Inputs · Forms", subtitle: "Wave-3 selection, input, and form controls")

            wave3SelectionRow
            wave3ChoiceRow
            wave3NumericRow
            wave3TextRow
            wave3RestyledRow
            wave3FormRowSample
        }
    }

    private var wave3SampleItems: [String] { ["Option A", "Option B", "Option C"] }

    private var wave3SearchableSelectItems: [String] {
        [
            "Alabama", "Alaska", "Arizona", "Arkansas", "California",
            "Colorado", "Connecticut", "Delaware", "Florida", "Georgia"
        ]
    }

    private var wave3SelectionRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Select, MultiSelect, Combobox, SearchableSelect — dropdowns now ALWAYS search; panel width ≥ field width")
            HStack(alignment: .top, spacing: AinkradSpacing.md) {
                // Wide field + long list: opening it shows the search field and
                // a panel floored to this 260pt field width.
                AinkradSelect(items: wave3SearchableSelectItems, selection: $wave3SelectSelection) { $0 }
                    .frame(width: 260)
                AinkradMultiSelect(items: wave3SampleItems, selection: $wave3MultiSelectSelection) { $0 }
                AinkradCombobox(
                    items: wave3SampleItems,
                    selection: $wave3ComboboxSelection,
                    text: $wave3ComboboxText
                ) { $0 }
                // Narrow field: panel floors to this 110pt width (content wider
                // than that still wins), and AinkradSearchableSelect is now just
                // an alias of the always-searchable AinkradSelect.
                AinkradSearchableSelect(
                    items: wave3SearchableSelectItems,
                    selection: $wave3SearchableSelectSelection,
                    label: { $0 },
                    placeholder: "Search states…"
                )
                .frame(width: 110)
            }
        }
    }

    private var wave3ChoiceRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Checkbox, Radio Group")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradCheckbox(isOn: $wave3CheckboxOn, label: "Enable feature")
                AinkradRadioGroup(options: wave3SampleItems, selection: $wave3RadioSelection) { $0 }
            }
        }
    }

    private var wave3NumericRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Stepper, Range Slider")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradStepper(value: $wave3StepperValue, in: 0...10)
                AinkradRangeSlider(range: $wave3RangeSliderValue, bounds: 0...1)
            }
        }
    }

    private var wave3TextRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Search Field, Text Area")
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradSearchField(text: $wave3SearchText, placeholder: "Search…")
                AinkradTextArea(text: $wave3TextAreaText, placeholder: "Text area")
            }
        }
    }

    private var wave3RestyledRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Restyled: Text Field, Secure Field, Toggle, Segmented Picker, Slider")
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradTextField(text: $wave3TextFieldText, placeholder: "Text field")
                AinkradSecureField(text: $wave3SecureFieldText, placeholder: "Secure field")
                HStack(spacing: AinkradSpacing.lg) {
                    AinkradToggle(isOn: $wave3ToggleOn)
                    AinkradSegmentedPicker(items: Array(0..<3), selection: $wave3SegmentedSelection) { "Item \($0)" }
                }
                AinkradSlider(value: $wave3SliderValue, in: 0...1)
            }
        }
    }

    private var wave3FormRowSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Form Row")
            AinkradFormRow(title: "Enable feature", help: "A checkbox in a form row") {
                AinkradCheckbox(isOn: $wave3CheckboxOn)
            }
        }
    }

    // MARK: - Wave 4: Navigation · Feedback

    private var wave4Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Navigation · Feedback", subtitle: "Wave-4 Cardinal HUD components")

            wave4NavigationRow
            wave4CommandNavRow
            wave4StatusSpinnerRow
            wave4BannerToastRow
            wave4TooltipPopoverRow
            wave4ConfirmDialogRow
            wave4StateViewsRow
        }
    }

    private var wave4Tabs: [String] { ["Overview", "Details", "History"] }
    private var wave4Breadcrumb: [String] { ["Ainkrad", "Projects", "Component Gallery"] }
    private var wave4CommandMenuItems: [(icon: String, label: String)] {
        [
            ("terminal", "Terminal"),
            ("gearshape", "Settings"),
            ("square.stack.3d.up", "Workspaces"),
            ("bolt.fill", "Actions")
        ]
    }
    private var wave4NavListItems: [String] { ["Dashboard", "Repositories", "Pull Requests", "Settings"] }

    private var wave4NavigationRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Tabs, Breadcrumb, Pagination")
            AinkradTabs(tabs: wave4Tabs, selection: $wave4TabsSelection) { $0 }
            AinkradBreadcrumb(items: wave4Breadcrumb)
            AinkradPagination(page: $wave4PaginationPage, pageCount: 5)
        }
    }

    private var wave4CommandNavRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Command Menu, Nav List")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradCommandMenu(
                    items: wave4CommandMenuItems.map(\.label),
                    selection: $wave4CommandMenuSelection,
                    icon: { label in wave4CommandMenuItems.first { $0.label == label }?.icon ?? "questionmark" },
                    label: { $0 }
                )
                .frame(width: 180)
                AinkradNavList(
                    items: wave4NavListItems,
                    selection: $wave4NavListSelection,
                    icon: { _ in "chevron.right" },
                    label: { $0 }
                )
                .frame(width: 200)
            }
        }
    }

    private var wave4StatusSpinnerRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Status Bar (accent & status kinds), Spinner")
            HStack(spacing: AinkradSpacing.lg) {
                VStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                    AinkradStatusBar(value: 0.75, kind: .accent)
                    AinkradStatusBar(value: 0.4, kind: .status(.warning))
                    AinkradStatusBar(value: 0.9, kind: .status(.danger))
                }
                .frame(width: 160)
                AinkradSpinner()
            }
        }
    }

    private var wave4BannerToastRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Banner (per status), Toast")
            VStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                ForEach(AinkradStatus.allCases, id: \.self) { status in
                    AinkradBanner(message: "\(String(describing: status).capitalized) banner message", status: status)
                }
            }
            FireToastButton()
        }
    }

    private var wave4TooltipPopoverRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Tooltip, Popover")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradButton(title: "Hover me", style: .ghost, action: {})
                    .ainkradTooltip("This is a Cardinal HUD tooltip")
                AinkradButton(title: "Show Popover", style: .secondary) {
                    wave4PopoverPresented = true
                }
                .ainkradPopover(isPresented: $wave4PopoverPresented) {
                    Text("Popover content")
                        .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground)
                }
            }
        }
    }

    private var wave4ConfirmDialogRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Confirm Dialog (default & destructive) — centers in the gallery app surface")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradButton(title: "Confirm…", style: .secondary) {
                    wave4ConfirmDialogPresented = true
                }
                AinkradButton(title: "Delete…", style: .danger) {
                    wave4DestructiveConfirmDialogPresented = true
                }
            }
        }
    }

    private var wave4StateViewsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Restyled: Empty State (with & without action), Error State, Loading State")
            HStack(spacing: AinkradSpacing.md) {
                AinkradEmptyState(icon: "tray", title: "Nothing here", message: "No items yet.",
                                  actionTitle: "Add Item", action: {})
                    .frame(height: 180)
                AinkradEmptyState(icon: "tray", title: "Nothing here", message: "No items yet.")
                    .frame(height: 180)
                AinkradErrorState(message: "Something went wrong.", retryTitle: "Retry", retry: {})
                    .frame(height: 180)
                AinkradLoadingState(label: "Loading…")
                    .frame(height: 180)
            }
        }
    }

    // MARK: - Wave 5: Data · Overlays

    private var wave5Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Data · Overlays", subtitle: "Wave-5 Cardinal HUD components")

            wave5ListRowsColumn
            wave5StatRowsColumn
            wave5IconGlyphRow
            wave5DataTableSample
            wave5MeterRow
            wave5AppTileRow
            wave5CodeBlockSample
            wave5LogViewSample
            wave5OverlayTriggersRow
        }
    }

    private var wave5ListRowsColumn: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("List Row (selected, trailing badge, right-click first row for a CUSTOM context menu)")
            VStack(spacing: AinkradSpacing.xs) {
                AinkradListRow(
                    isSelected: wave5ListRowSelection == "cpu-core-0",
                    onTap: { wave5ListRowSelection = "cpu-core-0" },
                    leading: { AinkradIconGlyph(systemName: "cpu", filled: true) },
                    title: "cpu-core-0",
                    subtitle: "4 threads · 3.2 GHz",
                    trailing: { AinkradBadge(text: "Active", status: .success) }
                )
                .ainkradContextMenu([
                    AinkradMenuItem(title: "Inspect", systemName: "magnifyingglass", action: {}),
                    AinkradMenuItem(title: "Restart", systemName: "arrow.clockwise", action: {}),
                    AinkradMenuItem(title: "Terminate", systemName: "xmark.octagon", isDestructive: true, action: {})
                ])

                AinkradListRow(
                    isSelected: wave5ListRowSelection == "gpu-0",
                    onTap: { wave5ListRowSelection = "gpu-0" },
                    leading: { AinkradIconGlyph(systemName: "cpu.fill") },
                    title: "gpu-0",
                    subtitle: "Metal · 16 GB",
                    trailing: { AinkradBadge(text: "Idle", status: .neutral) }
                )

                AinkradListRow(
                    leading: { AinkradIconGlyph(systemName: "network") },
                    title: "net-0",
                    trailing: { AinkradBadge(text: "Warning", status: .warning) }
                )
            }
        }
    }

    private var wave5StatRowsColumn: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Stat Row (per status)")
            VStack(spacing: 2) {
                AinkradStatRow(label: "Uptime", value: "14d 6h", status: .neutral)
                AinkradStatRow(label: "Load Avg", value: "0.42", status: .success)
                AinkradStatRow(label: "Temp", value: "78°C", status: .warning)
            }
        }
    }

    private var wave5IconGlyphRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Icon Glyph (outline & filled)")
            HStack(spacing: AinkradSpacing.md) {
                AinkradIconGlyph(systemName: "bolt")
                AinkradIconGlyph(systemName: "bolt.fill", filled: true)
                AinkradIconGlyph(systemName: "shield")
                AinkradIconGlyph(systemName: "shield.fill", filled: true)
                AinkradIconGlyph(systemName: "flame", size: 20)
                AinkradIconGlyph(systemName: "flame.fill", size: 20, filled: true)
            }
        }
    }

    private var wave5TableRows: [GalleryProcessRow] {
        [
            GalleryProcessRow(id: "1", name: "agentd", cpu: "12.4", status: "Running"),
            GalleryProcessRow(id: "2", name: "terminal-host", cpu: "3.1", status: "Running"),
            GalleryProcessRow(id: "3", name: "indexer", cpu: "44.8", status: "Busy"),
            GalleryProcessRow(id: "4", name: "sync-worker", cpu: "0.2", status: "Idle"),
            GalleryProcessRow(id: "5", name: "watcher", cpu: "1.6", status: "Idle")
        ]
    }

    private var wave5TableColumns: [AinkradTableColumn<GalleryProcessRow>] {
        [
            AinkradTableColumn(id: "name", title: "Process", cell: { $0.name }),
            AinkradTableColumn(id: "cpu", title: "CPU %", alignment: .trailing, cell: { $0.cpu }),
            .accessory(id: "status", title: "Status", alignment: .leading) { row in
                AinkradBadge(text: row.status,
                             status: row.status == "Running" ? .success : row.status == "Busy" ? .warning : .neutral)
            },
            .accessory(id: "actions") { _ in
                AinkradIconButton(systemName: "stop.fill", size: 22, tooltip: "Stop") {}
            }
        ]
    }

    private var wave5DataTableSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Data Table (sort by header; click, ⌘-click or ⇧-click rows to select)")
            AinkradDataTable(rows: wave5TableRows, columns: wave5TableColumns, sort: $wave5TableSort,
                             selection: $wave5TableSelection)
        }
    }

    private var wave5MeterRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Meter")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradMeter(value: 0.42, label: "CPU")
                AinkradMeter(value: 0.86, label: "Disk", kind: .status(.warning))
            }
        }
    }

    private var wave5AppTileRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("App Tile")
            HStack(spacing: AinkradSpacing.md) {
                AinkradAppTile(symbol: "terminal", title: "Terminal")
                AinkradAppTile(symbol: "gearshape", title: "Settings", isSelected: true)
            }
        }
    }

    private var wave5CodeBlockSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Code Block")
            AinkradCodeBlock(
                """
                func meterFraction(value: Double, total: Double) -> Double {
                    guard total > 0 else { return 0 }
                    return max(0, min(value / total, 1))
                }
                """,
                language: "swift"
            )
        }
    }

    /// Seed lines covering what the palette maps: plain stdout, 8-colour and
    /// bold codes, dim text, uncoloured stderr, and a source name long enough
    /// to be truncated in the source column.
    private static func sampleLog() -> AinkradLogBuffer {
        var log = AinkradLogBuffer()
        log.append("listening on :8080\n", source: "api")
        log.append("\u{1B}[32m✓\u{1B}[0m migrations applied (12)\n", source: "api")
        log.append("\u{1B}[33mWARN\u{1B}[0m slow query 812 ms: SELECT * FROM jobs\n", source: "api")
        log.append("\u{1B}[1;31mERROR\u{1B}[0m connection refused: db:5432\n", source: "runtime-head-hunter")
        log.append("retrying in 5s\n", stream: .stderr, source: "runtime-head-hunter")
        log.append("\u{1B}[2mdebug: pool size 16\u{1B}[0m\n", source: "api")
        log.append("\u{1B}[36mGET\u{1B}[0m /health 200 3 ms\n", source: "api")
        return log
    }

    private var wave5LogViewSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Log View (ticks every 2 s; turn Follow off and scroll up to read; select, ⌘F, copy)")
            HStack(spacing: AinkradSpacing.lg) {
                HStack(spacing: AinkradSpacing.sm) {
                    AinkradToggle(isOn: $wave5LogFollowing)
                    AinkradCaption("Follow")
                }
                HStack(spacing: AinkradSpacing.sm) {
                    AinkradToggle(isOn: $wave5LogShowsSource)
                    AinkradCaption("Source column")
                }
            }
            AinkradLogView(lines: wave5Log.all,
                           palette: AinkradANSIPalette(theme: galleryTokens, statusColors: galleryStatusColors),
                           foreground: galleryTokens.foreground,
                           showsSourcePrefix: wave5LogShowsSource,
                           isFollowing: wave5LogFollowing)
                .frame(height: 180)
                .background(ChamferShape(cut: AinkradRadius.sm).fill(galleryTokens.surface.opacity(0.9)))
                .task {
                    // A live tail, so follow mode has something to follow.
                    var tick = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        tick += 1
                        wave5Log.append("worker tick \(tick) ok\n", source: "sync-worker")
                    }
                }
        }
    }

    private var wave5OverlayTriggersRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Modal, Sheet, Drawer — scoped to the gallery app surface (attached at panel root)")
            HStack(spacing: AinkradSpacing.lg) {
                AinkradButton(title: "Show Modal", style: .secondary) { wave5ModalPresented = true }
                AinkradButton(title: "Show Sheet", style: .secondary) { wave5SheetPresented = true }
                AinkradButton(title: "Show Drawer", style: .secondary) { wave5DrawerPresented = true }
            }
        }
    }

    private func elevationSample(label: String, shadow: ShadowSpec) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AinkradRadius.sm)
                .fill(galleryTokens.surfaceElevated)
                .frame(width: 64, height: 40)
                .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            Text(label)
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.6))
        }
    }

    private var spacingSamples: [(label: String, value: CGFloat)] {
        [("xs", AinkradSpacing.xs), ("sm", AinkradSpacing.sm), ("md", AinkradSpacing.md),
         ("lg", AinkradSpacing.lg), ("xl", AinkradSpacing.xl), ("xxl", AinkradSpacing.xxl)]
    }

    private var radiusSamples: [(label: String, value: CGFloat)] {
        [("sm", AinkradRadius.sm), ("md", AinkradRadius.md), ("lg", AinkradRadius.lg), ("panel", AinkradRadius.panel)]
    }
}

/// Reads `\.ainkradToastCenter` from its OWN position in the view tree (a
/// genuine descendant of wherever `.ainkradToastHost()` is mounted), rather
/// than at `ComponentGalleryView`'s level. A `@Environment` read only sees
/// environment values set by a view's ANCESTORS — `.ainkradToastHost()` is
/// mounted on `panel`, a child `ComponentGalleryView` builds in its own
/// `body`, so `ComponentGalleryView` reading the environment on itself would
/// still see the pre-host default, never the center the host renders from.
/// A separate child view like this one, nested inside that same subtree, is
/// the correct place to read it.
/// Sample row for the Wave-5 `AinkradDataTable` demo — a fake process
/// readout with a few text columns, matching the table's v1 text-cell-only
/// contract.
private struct GalleryProcessRow: Identifiable {
    let id: String
    let name: String
    let cpu: String
    let status: String
}

private struct FireToastButton: View {
    @Environment(\.ainkradToastCenter) private var center

    var body: some View {
        AinkradButton(title: "Fire Toast", style: .secondary) {
            center.show("Sample toast message", status: .success)
        }
    }
}
#endif
