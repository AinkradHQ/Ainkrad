import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The App Store HUD overlay — browse the catalog and install / update /
/// uninstall / enable apps. Same HUD language as the Launcher / Settings.
struct AppStoreOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    @Bindable var store: AppStoreStore
    let onDismiss: () -> Void

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 248), spacing: skin.spacing.lg)] }

    var body: some View {
        let tokens = environment.themeManager.hostSkin
        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea().onTapGesture { onDismiss() }
                panel(tokens: tokens)
                    .frame(
                        width: min(max(900, geo.size.width * 0.82), 1120),
                        height: min(max(600, geo.size.height * 0.82), 760)
                    )
                    .offset(y: -30)
                if let box = store.lightbox {
                    screenshotLightbox(box, tokens: tokens)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: skin.motion.durations.d0_22), value: store.lightbox)
            .ainkradModal(
                isPresented: Binding(
                    get: { store.pendingReinstall != nil },
                    set: { if !$0 { store.cancelReinstall() } }),
                contentWidth: skin.size.s340
            ) {
                if let id = store.pendingReinstall {
                    reinstallPrompt(appID: id, tokens: tokens)
                }
            }
            // The kit modal's entrance runs on its own materialize timing;
            // driving it from the store's change keeps it animated.
            .animation(
                reduceMotion ? nil : skin.animation(skin.motion.materializeAnimation), value: store.pendingReinstall)
        }
        .task {
            // Paint instantly from the persisted catalog cache, then fetch the
            // live catalog so detail-page metadata (version, screenshots,
            // links) is current without requiring the manual refresh button —
            // a stale cache was hiding newly-published screenshots entirely.
            store.reloadRows()
            await store.refresh()
        }
    }

    /// The retained-data Restore/Reset prompt shown when reinstalling an app
    /// that left settings behind (AIN-149). The kit modal supplies the scrim,
    /// panel, entrance (skipped under Reduce Motion) and Esc/scrim dismissal,
    /// which cancel the reinstall.
    private func reinstallPrompt(appID: String, tokens: AinkradSkin) -> some View {
        let name = store.rows.first { $0.id == appID }?.displayName ?? appID
        return VStack(alignment: .leading, spacing: skin.size.s14) {
            Text("Reinstall \(name)")
                .font(AinkradFont.display(15, weight: .semibold))
                .foregroundStyle(tokens.color(\.foreground))
            Text("Previous settings for \(name) were kept. Restore them, or reset to defaults?")
                .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: skin.size.s10) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { store.cancelReinstall() }
                AinkradButton(title: "Reset to Defaults", style: .secondary) {
                    Task { await store.resetAndInstall(appID) }
                }
                AinkradButton(title: "Restore", style: .primary) { Task { await store.restoreAndInstall(appID) } }
            }
        }
    }

    private func panel(tokens: AinkradSkin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let row = store.selectedRow {
                themeFailureBanner(tokens: tokens).padding(.top, skin.size.s14)
                AppStoreDetailView(
                    entry: row.kind.isTheme ? nil : store.entry(for: row.id), row: row, tokens: tokens, isBusy: store.busy.contains(row.id),
                    onBack: { store.closeDetail() },
                    onInstall: {
                        environment.sounds.play(.install)
                        Task { await store.install(row.id) }
                    },
                    onUpdate: { Task { await store.update(row.id) } },
                    onUninstall: {
                        environment.sounds.play(.uninstall)
                        store.uninstall(row.id)
                    },
                    onToggleEnabled: {
                        environment.sounds.play(.toggle)
                        store.setEnabled($0, for: row.id)
                    },
                    onOpenScreenshot: { urls, index in
                        environment.sounds.play(.overlayOpen)
                        store.openLightbox(urls, at: index)
                    },
                    themeEntry: row.kind.isTheme ? store.themeEntry(for: row.id) : nil,
                    onApply: { store.apply(row.id) })
            } else {
                header(tokens: tokens)
                filterBar(tokens: tokens)
                themeFailureBanner(tokens: tokens)
                trustPostureBanner(tokens: tokens)
                loadFailureBanner(tokens: tokens)
                content(tokens: tokens)
            }
        }
        .hudPanelChrome(tokens: tokens)
        .onKeyPress(.escape) {
            if store.pendingReinstall != nil {
                // The reinstall prompt answers Esc first, as Cancel.
                store.cancelReinstall()
            } else if store.lightbox != nil {
                environment.sounds.play(.overlayClose)
                store.closeLightbox()
            } else if store.selectedAppID != nil {
                store.closeDetail()
            } else {
                onDismiss()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard store.lightbox != nil else { return .ignored }
            store.lightboxPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard store.lightbox != nil else { return .ignored }
            store.lightboxNext()
            return .handled
        }
    }

    // MARK: - Screenshot lightbox (AIN-147)

    /// Full-screen screenshot viewer: dark backdrop (click to close), the
    /// current image fit-scaled large, ⟨/⟩ wrap-around navigation + a "n / N"
    /// counter when the gallery has more than one image, and a close ✕.
    /// ESC/←/→ are handled by the panel's key handlers above (the panel keeps
    /// keyboard focus while this overlay is up). No kit component shows a
    /// full-screen image gallery, so this stays local, on skin tokens.
    private func screenshotLightbox(_ box: AppStoreStore.Lightbox, tokens: AinkradSkin) -> some View {
        ZStack {
            skin.color(.palette("black", skin.opacity.o82)).ignoresSafeArea()
                .onTapGesture {
                    environment.sounds.play(.overlayClose)
                    store.closeLightbox()
                }

            AsyncImage(url: box.urls[box.index]) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    VStack(spacing: skin.spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(skin.font(AinkradFontToken(sizeKey: "t28", scaled: false)))
                            .foregroundStyle(tokens.color(\.warning))
                        Text("Couldn't load image")
                            .font(AinkradFont.display(12))
                            .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o60))
                    }
                default:
                    AinkradSpinner(size: 36)
                }
            }
            .padding(skin.size.s48)
            .clipShape(ChamferShape(cut: skin.radius.md))
            .shadow(color: skin.color(.palette("black", skin.opacity.o60)), radius: skin.size.s30, y: skin.size.s10)
            .allowsHitTesting(false)  // clicks on the image fall through to nothing (backdrop closes)

            VStack {
                HStack {
                    Spacer()
                    AinkradIconButton(systemName: "xmark", tooltip: "Close (esc)") {
                        environment.sounds.play(.overlayClose)
                        store.closeLightbox()
                    }
                }
                Spacer()
                if box.urls.count > 1 {
                    AinkradChip(label: "\(box.index + 1) / \(box.urls.count)")
                }
            }
            .padding(skin.size.s20)

            if box.urls.count > 1 {
                HStack {
                    AinkradIconButton(systemName: "chevron.left", tooltip: "Previous (←)") {
                        store.lightboxPrevious()
                    }
                    Spacer()
                    AinkradIconButton(systemName: "chevron.right", tooltip: "Next (→)") { store.lightboxNext() }
                }
                .padding(.horizontal, skin.size.s18)
            }
        }
    }

    private func header(tokens: AinkradSkin) -> some View {
        HStack {
            Text("APP STORE").font(AinkradFont.display(14, weight: .semibold)).kerning(1)
                .foregroundStyle(tokens.color(\.foreground))
            Spacer()
            AinkradSegmentedPicker(items: AppStoreStore.Tab.allCases, selection: $store.tab) { tab in
                tab == .apps ? "Apps" : "Themes"
            }
            Spacer()
            // Refresh morphs to a spinner in place while refreshing — both
            // views stay mounted, only `.opacity` toggles. Local because the
            // kit icon button has no loading state.
            ZStack {
                AinkradIconButton(systemName: "arrow.clockwise", tooltip: "Refresh catalog") {
                    Task { await store.refresh() }
                }
                .opacity(store.isRefreshing ? 0 : 1)
                AinkradSpinner(size: 16)
                    .opacity(store.isRefreshing ? 1 : 0)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: skin.motion.durations.d0_2), value: store.isRefreshing)
            AinkradIconButton(systemName: "xmark", tooltip: "Close") { onDismiss() }
        }
        .padding(.horizontal, skin.size.s18).padding(.vertical, skin.size.s14)
    }

    private func filterBar(tokens: AinkradSkin) -> some View {
        let updateCount = store.currentRows.filter { $0.status == .updateAvailable }.count
        return HStack(spacing: skin.spacing.sm) {
            AinkradSegmentedPicker(items: AppStoreStore.Filter.allCases, selection: $store.filter) { filter in
                filterLabel(filter, updateCount: updateCount)
            }
            AinkradSearchField(
                text: $store.searchQuery, placeholder: store.tab == .apps ? "Search apps…" : "Search themes…")
                .frame(width: skin.size.s220)
            Spacer()
            if let error = store.error {
                Text(error.message).font(skin.font(AinkradFontToken(sizeKey: "t10", scaled: false)))
                    .foregroundStyle(tokens.color(\.warning))
                    .lineLimit(1)
                AinkradIconButton(systemName: "xmark.circle") { store.error = nil }
            }
        }
        .padding(.horizontal, skin.size.s18).padding(.vertical, skin.size.s10)
    }

    private func filterLabel(_ filter: AppStoreStore.Filter, updateCount: Int) -> String {
        switch filter {
        case .all: return "All"
        case .installed: return "Installed"
        case .updates: return updateCount > 0 ? "Updates (\(updateCount))" : "Updates"
        }
    }

    /// States plainly when plugin code is not being signature-verified.
    ///
    /// This build is not Developer-ID signed, so `PluginTrust` accepts any
    /// bundle — the alternative (demanding Developer-ID plugins from a host
    /// that has no such identity itself) rejects everything and ships an app
    /// with no apps. That is a defensible trade, but not a silent one: the
    /// user is trusting the catalog rather than the code, and should know it.
    /// Hidden entirely once a Developer-ID release is cut.
    @ViewBuilder private func trustPostureBanner(tokens: AinkradSkin) -> some View {
        if !PluginTrust.isVerifyingPluginSignatures {
            HStack(alignment: .top, spacing: skin.size.s6) {
                Image(systemName: "lock.open").font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text("Plugin signatures aren’t verified in this build")
                        .font(AinkradFont.display(12, weight: .semibold))
                    Text(
                        "Downloads are still checked against the catalog’s SHA-256, so the bytes match what was published — but who published them isn’t verified."
                    )
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o70))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(tokens.color(\.accentSecondary))
            .banner(tint: tokens.color(\.accentSecondary), fill: skin.opacity.o10, stroke: skin.opacity.o35, skin: skin)
        }
    }

    /// A refused theme install: the installer's problem lines (a bad checksum,
    /// an id mismatch, a key the host does not know), which the one-line
    /// `AppStoreError.message` would flatten to "Invalid app bundle.".
    @ViewBuilder private func themeFailureBanner(tokens: AinkradSkin) -> some View {
        if let failure = store.themeFailure {
            HStack(alignment: .top, spacing: skin.size.s6) {
                VStack(alignment: .leading, spacing: skin.spacing.xs) {
                    HStack(spacing: skin.size.s6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                        Text("\(failure.name) couldn’t be installed")
                            .font(AinkradFont.display(12, weight: .semibold))
                    }
                    .foregroundStyle(tokens.color(\.warning))
                    Text(failure.text)
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o75))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                AinkradIconButton(systemName: "xmark.circle", tooltip: "Dismiss") { store.themeFailure = nil }
            }
            .banner(tint: tokens.color(\.warning), fill: skin.opacity.o12, stroke: skin.opacity.o45, skin: skin)
        }
    }

    /// Surfaces plugins that were present on disk but refused to load this
    /// launch. Without this the failure is invisible: the loader records it and
    /// the app simply shows fewer apps, which reads as "nothing installed"
    /// rather than "something is wrong". Hidden entirely when nothing failed.
    @ViewBuilder private func loadFailureBanner(tokens: AinkradSkin) -> some View {
        let failures = store.loadFailures
        if !failures.isEmpty {
            VStack(alignment: .leading, spacing: skin.spacing.xs) {
                HStack(spacing: skin.size.s6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    Text(failures.count == 1 ? "1 app couldn’t be loaded" : "\(failures.count) apps couldn’t be loaded")
                        .font(AinkradFont.display(12, weight: .semibold))
                }
                .foregroundStyle(tokens.color(\.warning))
                ForEach(failures, id: \.url) { failure in
                    Text(AppStoreStore.failureText(failure))
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o75))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .banner(tint: tokens.color(\.warning), fill: skin.opacity.o12, stroke: skin.opacity.o45, skin: skin)
        }
    }

    @ViewBuilder private func content(tokens: AinkradSkin) -> some View {
        let rows = store.visibleRows
        if rows.isEmpty {
            if store.isRefreshing && store.rows.isEmpty {
                // First load, no data yet — centered spinner, not an empty state.
                AinkradSpinner(size: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let empty = store.emptyState
                AinkradEmptyState(icon: empty.icon, title: empty.title, message: empty.message)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: skin.spacing.lg) {
                    ForEach(rows) { row in
                        AppStoreCard(
                            row: row, tokens: tokens, isBusy: store.busy.contains(row.id),
                            onOpen: { store.openDetail(row.id) },
                            onInstall: {
                                environment.sounds.play(.install)
                                Task { await store.install(row.id) }
                            },
                            onUpdate: { Task { await store.update(row.id) } },
                            onUninstall: {
                                environment.sounds.play(.uninstall)
                                store.uninstall(row.id)
                            },
                            onToggleEnabled: {
                                environment.sounds.play(.toggle)
                                store.setEnabled($0, for: row.id)
                            },
                            onApply: { store.apply(row.id) })
                    }
                }
                .padding(skin.size.s18)
            }
        }
    }
}

extension AppEnvironment {
    /// Opens the App Store on the Themes tab — Settings → Appearance's "More
    /// themes…" row and the Setup appearance step's hint. A fresh install has
    /// only Neon, so these are how anyone finds another theme.
    func presentThemeStore() {
        appStoreStore.tab = .themes
        appStoreStore.closeDetail()
        isSettingsPresented = false
        isAppStorePresented = true
    }
}

extension View {
    /// The tinted notice behind the trust-posture and load-failure banners:
    /// a chamfered fill and border in `tint`, inset under the filter bar. Local
    /// because the kit has no notice banner.
    fileprivate func banner(tint: Color, fill: Double, stroke: Double, skin: AinkradSkin) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, skin.spacing.md).padding(.vertical, skin.size.s10)
            .background(ChamferShape(cut: skin.radius.sm).fill(tint.opacity(fill)))
            .overlay(ChamferShape(cut: skin.radius.sm).strokeBorder(tint.opacity(stroke), lineWidth: 1))
            .padding(.horizontal, skin.size.s18).padding(.bottom, skin.spacing.sm)
    }
}
