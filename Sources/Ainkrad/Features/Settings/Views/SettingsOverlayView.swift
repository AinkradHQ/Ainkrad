import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// The Settings overlay — the third summonable panel (⌘, or the Launcher's
/// Settings entry), in the same HUD language as the Launcher and Workspace
/// Overview. A left grouped sidebar (AINKRAD / BUILT-IN APPS) selects a
/// section shown in the detail pane on the right. See Settings Overlay Panel
/// — Direction.md.
///
/// Every section — WORKSPACE, INTELLIGENCE, BUILT-IN APPS, INSTALLED — is
/// catalog-driven; the sidebar and detail pane both read from
/// `HostSettingsCatalog.build(environment:)` via `navigator.selection`.
struct SettingsOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    let onDismiss: () -> Void

    @State private var navigator: SettingsNavigator
    @State private var pendingDeepLink: SettingsPath?

    @State private var query = ""
    @State private var hasNavigatedWithQuery = false
    @FocusState private var searchFocused: Bool
    /// The palette's keyboard highlight. Owned HERE, not by the palette,
    /// because the arrow keys arrive at the focused search field in the
    /// sidebar; the palette sits in the detail pane and is never in the focus
    /// chain, so a key handler installed inside it would never fire.
    @State private var paletteHighlight: Int?

    /// Built once per render pass, not once per reader. The sidebar reads it
    /// for every row (through `displayedPage`) and the detail pane again, and
    /// each read rebuilt every app's catalog, so opening Settings and every
    /// redraw after it did the whole build dozens of times. `body` clears it;
    /// the first read in the pass builds it inside `body`, so the view still
    /// observes everything the build reads.
    @State private var catalogCache = CatalogCache()
    private var catalog: SettingsCatalog {
        if let built = catalogCache.value { return built }
        let built = HostSettingsCatalog.build(environment: environment)
        catalogCache.value = built
        return built
    }

    private var searchMode: SettingsSearchMode {
        SettingsSearchMode(query: query, hasNavigated: hasNavigatedWithQuery)
    }
    private var index: SettingsCatalogIndex { SettingsCatalogIndex(catalog: catalog) }

    /// The page actually on screen. Resolves through `pendingDeepLink` (a
    /// field or group path) via `catalog.page(containing:)` so a deep-link's
    /// containing page renders on the very first frame — `navigator.selection`
    /// only catches up once `.task` runs, which is too late to avoid a flash
    /// of the empty state if relied on directly.
    private var displayedPage: SettingsPage? {
        catalog.page(containing: pendingDeepLink ?? navigator.selection)
    }

    /// The field to highlight/scroll to. Mirrors `SettingsNavigator.navigate`'s
    /// own rule (nil when the resolved path IS the page, i.e. there's nothing
    /// more specific to point at) so the pending and post-`.task` states agree.
    private var displayedHighlight: SettingsPath? {
        if let pendingDeepLink {
            return (displayedPage?.path == pendingDeepLink) ? nil : pendingDeepLink
        }
        return navigator.highlightedPath
    }

    /// `focusedAppID` opens the overlay directly on that app's settings —
    /// e.g. summoning Settings while a Terminal is focused lands on Terminal.
    /// Otherwise it lands on General — the natural top of the reordered sidebar.
    init(focusedAppID: String? = nil, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let initial = focusedAppID.map { SettingsPath(["app", $0]) } ?? SettingsPath(["workspace", "general"])
        _navigator = State(initialValue: SettingsNavigator(initial: initial))
    }

    /// Lands the overlay directly on a specific field — used by ⌘, from a
    /// focused app, error toasts, and the assistant. Old paths still resolve
    /// via `SettingsPathAliases` so links survive the IA restructure.
    init(deepLink: SettingsPath, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let resolved = SettingsPathAliases.resolve(deepLink)
        _navigator = State(initialValue: SettingsNavigator(initial: resolved))
        _pendingDeepLink = State(initialValue: resolved)
    }

    var body: some View {
        let tokens = environment.themeManager.hostSkin
        let _ = catalogCache.value = nil

        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                    // A shortcut still recording when Settings closes would
                    // rebind whatever key is pressed next, anywhere. A confirm
                    // left open must not reappear on the next visit either.
                    .onDisappear {
                        environment.settingsDrafts.recorder.stop()
                        environment.settingsDrafts.pendingConfirm = nil
                        environment.settingsDrafts.showsThemeFiles = false
                    }

                let size = SettingsGeometry.panelSize(in: geo.size)
                panel(tokens: tokens)
                    .frame(width: size.width, height: size.height)
                    .offset(y: SettingsMetrics.panelYOffset)
                    .ainkradConfirmDialog(
                        isPresented: Binding(
                            get: { environment.settingsDrafts.pendingConfirm != nil },
                            set: { if !$0 { environment.settingsDrafts.pendingConfirm = nil } }),
                        title: environment.settingsDrafts.pendingConfirm?.title ?? "",
                        message: environment.settingsDrafts.pendingConfirm?.message ?? "",
                        confirmTitle: environment.settingsDrafts.pendingConfirm?.action ?? "Confirm",
                        isDestructive: true
                    ) {
                        // Read at tap time: the request the dialog is showing.
                        environment.settingsDrafts.pendingConfirm?.onConfirm()
                    }
                    .ainkradModal(
                        isPresented: Binding(
                            get: { environment.settingsDrafts.showsThemeFiles },
                            set: { environment.settingsDrafts.showsThemeFiles = $0 }),
                        contentWidth: skin.size.s520
                    ) {
                        ThemeFilesSheet(issues: environment.themeManager.catalogIssues) {
                            environment.settingsDrafts.showsThemeFiles = false
                        }
                    }
            }
        }
    }

    private func panel(tokens: AinkradSkin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)

            HStack(spacing: 0) {
                sidebar(tokens: tokens)

                detail(tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .hudPanelChrome(tokens: tokens)
        .background(
            // `.onKeyPress` only fires for a view in the focus chain, so with
            // nothing focused inside the overlay (e.g. right after it opens)
            // a key-press handler never sees ⌘F at all. A hidden `Button`
            // with `.keyboardShortcut` is registered with the window's key
            // equivalent system instead of the responder/focus chain, so it
            // fires regardless of what — if anything — is focused.
            Button {  // design-lint: allow raw-control kit gap, keyboard-shortcut carrier
                searchFocused = true
            } label: {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        )
        .onKeyPress(.escape) {
            // An open confirm answers Esc first, as Cancel.
            if environment.settingsDrafts.pendingConfirm != nil {
                environment.settingsDrafts.pendingConfirm = nil
                return .handled
            }
            if environment.settingsDrafts.showsThemeFiles {
                environment.settingsDrafts.showsThemeFiles = false
                return .handled
            }
            // Agree with `SettingsSearchMode`'s own notion of "empty" — a
            // whitespace-only query is `.browsing`, so it must dismiss on
            // the first press rather than silently eating the whitespace.
            if searchMode != .browsing {
                query = ""
                return .handled
            }
            onDismiss()
            return .handled
        }
        .task {
            if let path = pendingDeepLink {
                navigator.navigate(to: path, in: catalog)
                pendingDeepLink = nil
            }
        }
    }

    private func header(tokens: AinkradSkin) -> some View {
        HStack(spacing: skin.spacing.md) {
            AinkradBrandChevron()
                .fill(tokens.color(\.accentSecondary))
                .frame(width: skin.size.s16, height: skin.size.s14)
                .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o90), radius: skin.size.s6)
            Text("SETTINGS")
                .font(AinkradFont.display(13, weight: .semibold))
                .kerning(4)
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
            Spacer()
            Text("esc")
                .font(AinkradFont.mono(9))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o35))
        }
        .padding(.horizontal, skin.size.s18)
        .frame(height: skin.size.s52)
    }

    // MARK: - Sidebar

    private func sidebar(tokens: AinkradSkin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AinkradSearchField(text: $query, placeholder: "Search settings", focus: $searchFocused)
                .padding(.horizontal, AinkradSpacing.md)
                .padding(.top, AinkradSpacing.md)
                .padding(.bottom, AinkradSpacing.sm)
                // ↑/↓/Return for the palette live HERE, on the ancestor of the
                // focused text field: key presses start at the focused view
                // and bubble up through its ancestors, so this is the nearest
                // place they can be seen while the user is typing. The palette
                // itself is in the detail pane and never focused.
                .onKeyPress(.downArrow) { movePaletteHighlight(1) }
                .onKeyPress(.upArrow) { movePaletteHighlight(-1) }
                .onKeyPress(.return) { activatePaletteHighlight() }
                .onChange(of: query) { _, _ in
                    hasNavigatedWithQuery = false
                    paletteHighlight = nil
                }

            sidebarList(tokens: tokens)
        }
        // Wider than `SettingsMetrics.sidebarWidth` (240): the kit row's title
        // (body, medium) truncated "Permissions & Sandbox" there. 268 is the
        // smallest size step that fits every page and app label at every text
        // size in Exo 2 and System, and up to Medium in JetBrains Mono — all the
        // combinations the old 13 pt row fitted.
        .frame(width: skin.size.s268, alignment: .topLeading)
    }

    /// The results the palette is currently showing, or `nil` when the palette
    /// isn't on screen — the keys must stay out of the text field's way while
    /// browsing or filtering.
    private var paletteResults: [SettingsSearchResult]? {
        guard case .palette(let q) = searchMode else { return nil }
        return index.search(q, currentPage: navigator.selection)
    }

    private func movePaletteHighlight(_ delta: Int) -> KeyPress.Result {
        guard let results = paletteResults, !results.isEmpty else { return .ignored }
        paletteHighlight = commandMenuHighlightMoved(paletteHighlight, delta: delta, count: results.count)
        return .handled
    }

    private func activatePaletteHighlight() -> KeyPress.Result {
        guard let results = paletteResults, let index = paletteHighlight,
            results.indices.contains(index)
        else { return .ignored }
        navigator.navigate(to: results[index].path, in: catalog)
        hasNavigatedWithQuery = true
        return .handled
    }

    private func sidebarList(tokens: AinkradSkin) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.spacing.xs) {
                ForEach(SettingsPageGroup.allCases, id: \.self) { group in
                    let pages = catalog.pages(in: group)
                    if !pages.isEmpty {
                        AinkradSectionHeader(title: group.title)
                            .padding(.top, group == .workspace ? 0 : skin.spacing.md)
                        ForEach(pages) { page in
                            sidebarRow(page: page, tokens: tokens)
                        }
                    }
                }
            }
            .padding(skin.spacing.md)
        }
        .scrollContentBackground(.hidden)
    }

    /// A catalog-driven sidebar row for any page in any group.
    private func sidebarRow(page: SettingsPage, tokens: AinkradSkin) -> some View {
        let isSelected = displayedPage?.path == page.path
        return AinkradListRow(
            isSelected: isSelected,
            onTap: { selectPage(page) },
            leading: {
                appTile(
                    appID: page.appID, systemIcon: page.icon, size: skin.size.s22, isSelected: isSelected,
                    tokens: tokens)
            },
            title: page.title,
            trailing: {
                // Read here rather than at catalog-build time so the count
                // stays live while the overlay is open (Skills proposals).
                if let badgeCount = page.badge?(), badgeCount > 0 {
                    AinkradBadge(text: "\(badgeCount)", tint: tokens.color(\.accentSecondary))
                }
            }
        )
        .overlay(
            AinkradCornerBrackets(length: skin.size.s7)
                .stroke(
                    isSelected ? tokens.color(\.accentSecondary).opacity(skin.opacity.o90) : .clear,
                    lineWidth: 1.3 * skin.bracketStrokeScale)
                .padding(skin.size.s1)
        )
        // The kit row takes its tap as a gesture; these keep the row one
        // pressable accessibility element, as the plain button it replaced was.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selectPage(page) }
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: isSelected)
    }

    private func selectPage(_ page: SettingsPage) {
        navigator.selection = page.path
        navigator.clearHighlight()
        pendingDeepLink = nil
        // A sidebar tap is an unambiguous "take me to this page"
        // instruction — it must always show that page, in BOTH the
        // palette and filtering modes, not just leave the palette
        // sitting inertly on screen. Routed through the real
        // SettingsSearchMode.afterSidebarTap transition so production
        // and the sidebar-tap tests exercise the same code path.
        hasNavigatedWithQuery = searchMode.afterSidebarTap().query != nil
    }

    /// Shared tile renderer: the theme's neon artwork for a registered app, or
    /// a tinted SF Symbol fallback. Used by both sidebar rows and the app
    /// settings identity header.
    @ViewBuilder
    private func appTile(appID: String?, systemIcon: String, size: CGFloat, isSelected: Bool, tokens: AinkradSkin)
        -> some View
    {
        if appID != nil {
            // A registered app: its live neon tile, following the active theme.
            NeonAppTile(symbol: systemIcon, tokens: tokens, size: size)
        } else {
            // A fixed settings section (General, Sound, …): a tinted SF Symbol.
            Image(systemName: systemIcon)
                .font(.system(size: size * 0.6))  // design-lint: allow font-size kit-gap settingsGlyphRatio
                .foregroundStyle(isSelected ? tokens.color(\.accentSecondary) : tokens.color(\.foreground).opacity(skin.opacity.o55))
                .frame(width: size, height: size)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(tokens: AinkradSkin) -> some View {
        switch searchMode {
        case .palette(let q):
            SettingsPaletteView(
                results: index.search(q, currentPage: navigator.selection), query: q,
                highlight: $paletteHighlight
            ) { path in
                navigator.navigate(to: path, in: catalog)
                hasNavigatedWithQuery = true
            }
        case .filtering(let q):
            if let page = displayedPage {
                VStack(alignment: .leading, spacing: 0) {
                    filterBanner(query: q, tokens: tokens)
                    SettingsPageView(
                        page: page,
                        matchedPaths: index.matchedPaths(q, on: page),
                        highlightedPath: displayedHighlight
                    )
                    .id(page.path)
                }
            } else {
                AinkradEmptyState(
                    icon: "gearshape", title: "Nothing here",
                    message: "That settings page is no longer available.")
            }
        case .browsing:
            if let page = displayedPage {
                // One identity per page: the view's selected tab is `@State`,
                // and reused across pages it carried the last page's tab over —
                // the content clamped to a real tab while the tab bar
                // highlighted none. A fresh view opens on the first tab (or
                // the deep-linked one).
                SettingsPageView(page: page, highlightedPath: displayedHighlight)
                    .id(page.path)
            } else {
                AinkradEmptyState(
                    icon: "gearshape", title: "Nothing here",
                    message: "That settings page is no longer available.")
            }
        }
    }

    /// Makes the filter escapable — a filter you cannot see or exit is the
    /// disorienting part of System Settings' version, which we're
    /// deliberately not copying.
    private func filterBanner(query: String, tokens: AinkradSkin) -> some View {
        HStack(spacing: skin.spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(skin.font(AinkradFontToken(sizeKey: "t10", scaled: false)))
                .foregroundStyle(tokens.color(\.accentSecondary).opacity(skin.opacity.o85))
            Text("Filtering by \u{201C}\(query)\u{201D} — non-matching settings are dimmed")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o60))
            Spacer(minLength: skin.spacing.sm)
            AinkradButton(title: "Clear", style: .ghost) { self.query = "" }
        }
        .padding(.horizontal, skin.size.s18)
        .frame(height: skin.size.s34)
    }

}

/// Holds one render pass's catalog. A class so `body` can reset it without
/// that write being a state change that re-runs `body`.
private final class CatalogCache {
    var value: SettingsCatalog?
}
