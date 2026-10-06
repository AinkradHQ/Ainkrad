import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// Four corner brackets — the targeting-cursor treatment for a selection.
/// The kit's `AinkradCornerBrackets` is the same path; the alias keeps the
/// callers in other areas compiling until their area PRs move onto the kit
/// name, and then it goes.
typealias TargetingBrackets = AinkradCornerBrackets

/// The ⌘K summon: the workspace behind dims and blurs (see RootView), and
/// a glowing command deck floats above it — command field, Spotlight-style
/// app rows with the neon tile artwork, targeting brackets on the
/// selection. Apps only: workspace management lives on its own surface.
struct LauncherView: View {
    /// Plain value snapshot of an app's display fields — iterating SwiftUI
    /// containers over `BuiltInApp.Type` metatypes crashes the Xcode 27
    /// beta SILGen (same workaround as BuiltInAppsSettingsView).
    private struct AppRow: Identifiable {
        let id: String
        let displayName: String
        let icon: String
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @Bindable var store: LauncherStore
    let onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex = 0

    /// Apps-per-row in grid mode; also the up/down arrow step.
    private static let gridColumns = 4

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }

    private var viewMode: LauncherViewMode { environment.generalSettingsStore.launcherViewMode }
    private var isGrid: Bool { viewMode == .grid }

    /// Sentinel id for the Settings entry — Settings is a summonable overlay,
    /// not a registered app, so it rides in the results as a system action.
    private static let settingsRowID = "settings"
    private static let appStoreRowID = "appStore"
    #if DEBUG
    /// DEBUG-only system action — never appears in a release build's
    /// Launcher (Slice 1b Task 8).
    private static let galleryRowID = "componentGallery"
    #endif

    private var appRows: [AppRow] {
        var rows = store.appResults.map { AppRow(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
        if store.query.isEmpty || fuzzyMatches(query: store.query, target: "Settings") {
            rows.append(AppRow(id: Self.settingsRowID, displayName: "Settings", icon: "gearshape"))
        }
        if store.query.isEmpty || fuzzyMatches(query: store.query, target: "App Store") {
            rows.append(AppRow(id: Self.appStoreRowID, displayName: "App Store", icon: "bag"))
        }
        #if DEBUG
        if store.query.isEmpty || fuzzyMatches(query: store.query, target: "Component Gallery") {
            rows.append(AppRow(id: Self.galleryRowID, displayName: "Component Gallery", icon: "swatchpalette"))
        }
        #endif
        return rows
    }

    var body: some View {
        let results = appRows

        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                panel(results: results)
                    .frame(width: min(max(680, geo.size.width * 0.55), 820))
                    .offset(y: -60)
            }
        }
        .onAppear { isSearchFocused = true }
    }

    private func panel(results: [AppRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AinkradCommandField(
                "Summon an app…", text: $store.query, focus: $isSearchFocused,
                onArrow: { move($0, count: results.count) },
                onSubmit: { select(results) },
                onEscape: { dismiss() }
            )

            Text("APPS")
                .font(AinkradFont.mono(9, weight: .medium))
                .kerning(2.5)
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o40))
                .padding(.horizontal, skin.size.s18)
                .padding(.top, skin.size.s14)
                .padding(.bottom, skin.size.s6)

            if results.isEmpty {
                Text("No matching apps")
                    .font(AinkradFont.display(13))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o35))
                    .padding(.horizontal, skin.size.s18)
                    .padding(.vertical, skin.size.s14)
            } else if isGrid {
                gridView(results: results)
            } else {
                VStack(spacing: skin.size.s2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isSelected: index == selectedIndex)
                            .onTapGesture {
                                selectedIndex = index
                                select(results)
                            }
                    }
                }
                .padding(.horizontal, skin.size.s10)
                .padding(.bottom, skin.size.s10)
            }

            footer
        }
        // The user's overlay opacity and blur settings, as every summoned
        // overlay reads them.
        .ainkradOverlayChrome(
            backgroundOpacity: environment.generalSettingsStore.overlayBackgroundOpacity,
            blurEnabled: environment.generalSettingsStore.overlayBlurEnabled,
            blending: .withinWindow
        )
        .onChange(of: store.query) { _, _ in selectedIndex = 0 }
    }

    private func rowView(_ row: AppRow, isSelected: Bool) -> some View {
        AinkradListRow(
            isSelected: isSelected,
            leading: { tile(for: row, size: skin.size.s32) },
            title: row.displayName,
            trailing: {
                if isSelected {
                    Text("↩")
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(tokens.color(\.accentSecondary).opacity(skin.opacity.o80))
                }
            }
        )
        .overlay(
            AinkradCornerBrackets()
                .stroke(isSelected ? tokens.color(\.accentSecondary).opacity(skin.opacity.o90) : .clear, lineWidth: 1.5)
                .padding(skin.size.s1)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: skin.motion.durations.d0_12), value: selectedIndex)
    }

    /// The app's neon tile, drawn live from the active theme around its SF Symbol.
    private func tile(for row: AppRow, size: CGFloat) -> some View {
        NeonAppTile(
            symbol: row.icon, tokens: tokens, size: size, badge: badge(for: row),
            badgeStatus: badgeStatus(for: row))
    }

    /// Unread events this app has published, for its tile badge. Nil until the
    /// feed exists, so the launcher renders unchanged during bootstrap.
    /// The colour the count should be. A fixed accent read GREEN on a tile
    /// whose count is usually failures.
    private func badgeStatus(for row: AppRow) -> AinkradStatus? {
        guard let center = environment.signalCenter,
            let worst = center.worstUnreadSeverity(for: .app(appID: row.id))
        else { return nil }
        return SignalPresentation.status(for: worst)
    }

    private func badge(for row: AppRow) -> String? {
        guard let center = environment.signalCenter else { return nil }
        return SignalBadgeModel.badgeText(center.unreadCount(for: .app(appID: row.id)))
    }

    // MARK: - Grid mode

    private func gridView(results: [AppRow]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: skin.spacing.sm), count: Self.gridColumns)
        return LazyVGrid(columns: columns, spacing: skin.spacing.sm) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                gridCell(row, isSelected: index == selectedIndex)
                    .onTapGesture {
                        selectedIndex = index
                        select(results)
                    }
            }
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.spacing.md)
    }

    private func gridCell(_ row: AppRow, isSelected: Bool) -> some View {
        VStack(spacing: skin.spacing.sm) {
            tile(for: row, size: skin.size.s46)
            Text(row.displayName)
                .font(AinkradFont.display(11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(tokens.color(\.foreground).opacity(isSelected ? skin.opacity.o95 : skin.opacity.o70))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.spacing.md)
        .background(
            ChamferShape(cut: skin.radius.md).fill(tokens.color(\.accentSecondary).opacity(isSelected ? skin.opacity.o12 : 0))
        )
        .overlay(
            AinkradCornerBrackets(length: skin.size.s10)
                .stroke(isSelected ? tokens.color(\.accentSecondary).opacity(skin.opacity.o90) : .clear, lineWidth: 1.5)
                .padding(skin.size.s2)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: skin.motion.durations.d0_12), value: selectedIndex)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("↑↓ navigate    ↩ open    esc dismiss")
                .font(AinkradFont.mono(9))
                .kerning(0.5)
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o35))
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.bottom, skin.spacing.md)
    }

    /// Moves the selection for an arrow key; `false` when the key is not the
    /// Launcher's to take, so the caret gets it.
    private func move(_ arrow: AinkradArrow, count: Int) -> Bool {
        guard let delta = launcherArrowStep(arrow, isGrid: isGrid, columns: Self.gridColumns) else { return false }
        selectedIndex = launcherSelection(selectedIndex, movedBy: delta, count: count)
        return true
    }

    private func select(_ results: [AppRow]) {
        guard results.indices.contains(selectedIndex) else { return }
        let row = results[selectedIndex]

        if row.id == Self.settingsRowID {
            environment.isSettingsPresented = true
            dismiss()
            return
        }

        if row.id == Self.appStoreRowID {
            environment.isAppStorePresented = true
            dismiss()
            return
        }

        #if DEBUG
        if row.id == Self.galleryRowID {
            environment.isComponentGalleryPresented = true
            dismiss()
            return
        }
        #endif

        guard let app = store.appResults.first(where: { $0.id == row.id }) else { return }
        store.selectApp(app)
        environment.sounds.play(.appOpen)
        dismiss()
    }

    private func dismiss() {
        store.query = ""
        selectedIndex = 0
        onDismiss()
    }
}
