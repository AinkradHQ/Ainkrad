import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The App Store HUD overlay — browse the catalog and install / update /
/// uninstall / enable apps. Same HUD language as the Launcher / Settings.
struct AppStoreOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Bindable var store: AppStoreStore
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 248), spacing: 16)]

    var body: some View {
        let tokens = environment.themeManager.tokens
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity).ignoresSafeArea().onTapGesture { onDismiss() }
                panel(tokens: tokens)
                    .frame(
                        width: min(max(900, geo.size.width * 0.82), 1120),
                        height: min(max(600, geo.size.height * 0.82), 760)
                    )
                    .offset(y: -30)
                if let id = store.pendingReinstall {
                    reinstallModal(appID: id, tokens: tokens)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.94).combined(with: .opacity))
                }
                if let box = store.lightbox {
                    screenshotLightbox(box, tokens: tokens)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: store.pendingReinstall)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: store.lightbox)
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
    /// that left settings behind — same HUD chrome as the rest of the
    /// overlay, with a scale/opacity entrance and pressable buttons (AIN-149).
    /// Skipped under Reduce Motion.
    private func reinstallModal(appID: String, tokens: DesignTokens) -> some View {
        let name = store.rows.first { $0.id == appID }?.displayName ?? appID
        return ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { store.cancelReinstall() }
            VStack(alignment: .leading, spacing: 14) {
                Text("Reinstall \(name)")
                    .font(AinkradFont.display(15, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("Previous settings for \(name) were kept. Restore them, or reset to defaults?")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    AinkradButton(title: "Cancel", style: .ghost) { store.cancelReinstall() }
                    AinkradButton(title: "Reset to Defaults", style: .secondary) {
                        Task { await store.resetAndInstall(appID) }
                    }
                    AinkradButton(title: "Restore", style: .primary) { Task { await store.restoreAndInstall(appID) } }
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(ChamferShape(cut: AinkradRadius.panel).fill(tokens.surface))
            .overlay(
                ChamferShape(cut: AinkradRadius.panel).strokeBorder(tokens.accentPrimary.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
        .onKeyPress(.escape) {
            store.cancelReinstall()
            return .handled
        }
    }

    private func panel(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let row = store.selectedRow {
                AppStoreDetailView(
                    entry: store.entry(for: row.id), row: row, tokens: tokens, isBusy: store.busy.contains(row.id),
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
                    })
            } else {
                header(tokens: tokens)
                filterBar(tokens: tokens)
                trustPostureBanner(tokens: tokens)
                loadFailureBanner(tokens: tokens)
                content(tokens: tokens)
            }
        }
        .hudPanelChrome(tokens: tokens)
        .onKeyPress(.escape) {
            if store.lightbox != nil {
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
    /// keyboard focus while this overlay is up, same as the reinstall modal).
    private func screenshotLightbox(_ box: AppStoreStore.Lightbox, tokens: DesignTokens) -> some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture {
                    environment.sounds.play(.overlayClose)
                    store.closeLightbox()
                }

            AsyncImage(url: box.urls[box.index]) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(tokens.accentTertiary)
                        Text("Couldn't load image")
                            .font(AinkradFont.display(12))
                            .foregroundStyle(tokens.foreground.opacity(0.6))
                    }
                default:
                    AinkradSpinner(size: 36)
                }
            }
            .padding(48)
            .clipShape(ChamferShape(cut: AinkradRadius.md))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .allowsHitTesting(false)  // clicks on the image fall through to nothing (backdrop closes)

            VStack {
                HStack {
                    Spacer()
                    AinkradIconButton(systemName: "xmark") {
                        environment.sounds.play(.overlayClose)
                        store.closeLightbox()
                    }
                    .help("Close (esc)")
                }
                Spacer()
                if box.urls.count > 1 {
                    Text("\(box.index + 1) / \(box.urls.count)")
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(tokens.surfaceElevated.opacity(0.85)))
                }
            }
            .padding(20)

            if box.urls.count > 1 {
                HStack {
                    AinkradIconButton(systemName: "chevron.left") { store.lightboxPrevious() }
                        .help("Previous (←)")
                    Spacer()
                    AinkradIconButton(systemName: "chevron.right") { store.lightboxNext() }
                        .help("Next (→)")
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack {
            Text("APP STORE").font(AinkradFont.display(14, weight: .semibold)).kerning(1)
                .foregroundStyle(tokens.foreground)
            Spacer()
            // Refresh morphs to a spinner in place while refreshing — both
            // views stay mounted, only `.opacity` toggles, mirroring
            // AppStoreActionControls.actionButton's busy-morph.
            ZStack {
                AinkradIconButton(systemName: "arrow.clockwise") { Task { await store.refresh() } }
                    .opacity(store.isRefreshing ? 0 : 1)
                AinkradSpinner(size: 16)
                    .opacity(store.isRefreshing ? 1 : 0)
            }
            .help("Refresh catalog")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isRefreshing)
            AinkradIconButton(systemName: "xmark") { onDismiss() }
                .help("Close")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func filterBar(tokens: DesignTokens) -> some View {
        let updateCount = store.rows.filter { $0.status == .updateAvailable }.count
        return HStack(spacing: 8) {
            AinkradSegmentedPicker(items: AppStoreStore.Filter.allCases, selection: $store.filter) { filter in
                filterLabel(filter, updateCount: updateCount)
            }
            AinkradSearchField(text: $store.searchQuery, placeholder: "Search apps…")
                .frame(width: 220)
            Spacer()
            if let error = store.error {
                Text(errorText(error)).font(.system(size: 10)).foregroundStyle(tokens.accentTertiary)
                    .lineLimit(1)
                AinkradIconButton(systemName: "xmark.circle") { store.error = nil }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
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
    @ViewBuilder private func trustPostureBanner(tokens: DesignTokens) -> some View {
        if !PluginTrust.isVerifyingPluginSignatures {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.open").font(.system(size: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin signatures aren’t verified in this build")
                        .font(AinkradFont.display(12, weight: .semibold))
                    Text(
                        "Downloads are still checked against the catalog’s SHA-256, so the bytes match what was published — but who published them isn’t verified."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(tokens.accentSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.accentSecondary.opacity(0.10)))
            .overlay(
                ChamferShape(cut: AinkradRadius.sm).strokeBorder(tokens.accentSecondary.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 18).padding(.bottom, 8)
        }
    }

    /// Surfaces plugins that were present on disk but refused to load this
    /// launch. Without this the failure is invisible: the loader records it and
    /// the app simply shows fewer apps, which reads as "nothing installed"
    /// rather than "something is wrong". Hidden entirely when nothing failed.
    @ViewBuilder private func loadFailureBanner(tokens: DesignTokens) -> some View {
        let failures = store.loadFailures
        if !failures.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(failures.count == 1 ? "1 app couldn’t be loaded" : "\(failures.count) apps couldn’t be loaded")
                        .font(AinkradFont.display(12, weight: .semibold))
                }
                .foregroundStyle(tokens.accentTertiary)
                ForEach(failures, id: \.url) { failure in
                    Text(AppStoreStore.failureText(failure))
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.accentTertiary.opacity(0.12)))
            .overlay(
                ChamferShape(cut: AinkradRadius.sm).strokeBorder(tokens.accentTertiary.opacity(0.45), lineWidth: 1)
            )
            .padding(.horizontal, 18).padding(.bottom, 8)
        }
    }

    @ViewBuilder private func content(tokens: DesignTokens) -> some View {
        let rows = store.visibleRows
        if rows.isEmpty {
            if store.isRefreshing && store.rows.isEmpty {
                // First load, no data yet — centered spinner, not an empty state.
                AinkradSpinner(size: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AinkradEmptyState(icon: emptyIcon, title: emptyTitle, message: emptyText)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
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
                            })
                    }
                }
                .padding(18)
            }
        }
    }

    private var emptyText: String {
        let trimmedQuery = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { return "No apps match \"\(trimmedQuery)\"." }
        switch store.filter {
        case .all: return "No apps available — check back later."
        case .installed: return "Nothing installed yet."
        case .updates: return "Everything is up to date."
        }
    }

    private var emptyTitle: String {
        let trimmedQuery = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { return "No Matches" }
        switch store.filter {
        case .all: return "No Apps"
        case .installed: return "Nothing Installed"
        case .updates: return "Up to Date"
        }
    }

    private var emptyIcon: String {
        let trimmedQuery = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { return "magnifyingglass" }
        switch store.filter {
        case .all: return "square.grid.2x2"
        case .installed: return "shippingbox"
        case .updates: return "checkmark.seal"
        }
    }

    private func errorText(_ e: AppStoreError) -> String {
        switch e {
        case .download: return "Download failed."
        case .checksumMismatch: return "Integrity check failed."
        case .unpack: return "Could not unpack."
        case .invalidBundle: return "Invalid app bundle."
        case .notInstalled(let id): return "\(id) is not available."
        case .notNewer: return "Already up to date."
        }
    }
}
