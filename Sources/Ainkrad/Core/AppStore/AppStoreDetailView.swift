import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The App Store's per-app detail page (AIN-147): large icon, name, author,
/// version, long description, screenshot gallery, links, and the primary
/// action + enable/uninstall — reusing the exact same `AppStoreStore`
/// actions `AppStoreCard` uses in the grid. `AppStoreOverlayView` shows this
/// in place of the grid while `store.selectedAppID != nil`.
struct AppStoreDetailView: View {
    /// The full catalog record, when the app is in the cached catalog. `nil`
    /// for a built-in with no catalog entry — the view falls back to what
    /// `row` carries.
    let entry: CatalogEntry?
    let row: AppStoreRow
    let tokens: AinkradSkin
    let isBusy: Bool
    let onBack: () -> Void
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void
    /// Opens the full-screen lightbox on the tapped screenshot (gallery, index).
    let onOpenScreenshot: ([URL], Int) -> Void
    /// Themes tab: the store entry (screenshots), and Apply.
    var themeEntry: ThemeCatalogEntry? = nil
    var onApply: () -> Void = {}

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s22) {
                backButton
                header
                VStack(alignment: .leading, spacing: skin.spacing.sm) {
                    AinkradSectionHeader(title: "Description")
                    Text(longDescriptionText)
                        .font(skin.font(AinkradFontToken(sizeKey: "t13", scaled: false)))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o80))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(informationLine)
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
                }
                if row.kind.isTheme, let appearances = row.appearancesText {
                    VStack(alignment: .leading, spacing: skin.spacing.sm) {
                        AinkradSectionHeader(title: row.kind == .theme ? "Appearances" : "Appearance")
                        AinkradChip(label: appearances)
                    }
                }
                if row.swatch.count == 3 {
                    VStack(alignment: .leading, spacing: skin.spacing.sm) {
                        AinkradSectionHeader(title: "Colours")
                        HStack(spacing: skin.spacing.sm) {
                            ForEach(Array(zip(["Background", "Accent", "Secondary"], row.swatch)), id: \.0) { label, color in
                                AinkradSwatchChip(label: label, swatch: color)
                            }
                        }
                    }
                }
                if let secretKeys = requiredSecretKeys {
                    VStack(alignment: .leading, spacing: skin.spacing.sm) {
                        AinkradSectionHeader(title: "Requires Secrets")
                        requiredSecretsRow(secretKeys)
                    }
                }
                if let screenshots = entry?.screenshots ?? themeEntry?.screenshots, !screenshots.isEmpty {
                    VStack(alignment: .leading, spacing: skin.spacing.sm) {
                        AinkradSectionHeader(title: "Screenshots")
                        screenshotGallery(screenshots)
                    }
                }
                if let links = entry?.links, !links.isEmpty {
                    VStack(alignment: .leading, spacing: skin.spacing.sm) {
                        AinkradSectionHeader(title: "Links")
                        linksRow(links)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(skin.spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var backButton: some View {
        AinkradButton(title: "Back", style: .ghost, icon: "chevron.left", action: onBack)
            .help("Back to catalog")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: skin.size.s18) {
            AinkradAppTile(symbol: row.icon, size: 88)
            VStack(alignment: .leading, spacing: skin.size.s5) {
                Text(row.displayName)
                    .font(AinkradFont.display(20, weight: .semibold))
                    .foregroundStyle(tokens.color(\.foreground))
                if let author = entry?.author ?? row.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o60))
                }
                Text(row.versionLine)
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
                actions.padding(.top, skin.spacing.xs)
            }
            Spacer()
        }
    }

    private var longDescriptionText: String {
        let text = entry?.longDescription ?? row.description
        return text.isEmpty ? " " : text
    }

    /// A readable label for the row's provenance.
    private var kindLabel: String {
        switch row.kind {
        case .builtIn: return "Built-in"
        case .plugin: return "Plugin"
        case .mcpServer: return "MCP Server"
        case .theme: return "Theme"
        case .colorScheme: return "Colour Scheme"
        }
    }

    /// Secret env/header key NAMES the MCP server needs (never values — those
    /// are supplied later in the MCP manager). `nil` for non-MCP rows or an
    /// MCP entry that needs no secrets.
    private var requiredSecretKeys: [String]? {
        guard let mcp = entry?.mcp else { return nil }
        let keys = mcp.envKeys + mcp.headerKeys
        return keys.isEmpty ? nil : keys
    }

    /// `version · author · kind` — author omitted when nil/empty.
    private var informationLine: String {
        var parts = [row.versionLine]
        if let author = entry?.author ?? row.author, !author.isEmpty { parts.append(author) }
        parts.append(kindLabel)
        return parts.joined(separator: " · ")
    }

    /// The shared Install/Update/Enable/Disable/Uninstall controls (AIN-149)
    /// — identical to `AppStoreCard`'s, just rendered at the `.detail`
    /// size that fits the detail header.
    private var actions: some View {
        AppStoreActionControls(
            row: row, tokens: tokens, isBusy: isBusy, style: .detail,
            onInstall: onInstall, onUpdate: onUpdate, onUninstall: onUninstall, onToggleEnabled: onToggleEnabled,
            onApply: onApply)
    }

    // MARK: - Screenshot gallery

    private func screenshotGallery(_ urls: [URL]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: skin.spacing.md) {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    screenshot(url, in: urls, at: index)
                }
            }
        }
    }

    private func screenshot(_ url: URL, in urls: [URL], at index: Int) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                screenshotBox(systemImage: "exclamationmark.triangle", tint: tokens.color(\.warning))
            default:
                screenshotBox(systemImage: nil, tint: tokens.color(\.foreground))
            }
        }
        .frame(width: skin.size.s260, height: skin.size.s164)
        .clipShape(skin.shape(cut: skin.radius.md))
        .overlay(
            skin.shape(cut: skin.radius.md).strokeBorder(tokens.color(\.foreground).opacity(skin.opacity.o10), lineWidth: 1)
        )
        .contentShape(skin.shape(cut: skin.radius.md))
        .onTapGesture { onOpenScreenshot(urls, index) }
        .help("View full size")
    }

    private func screenshotBox(systemImage: String?, tint: Color) -> some View {
        ZStack {
            skin.shape(cut: skin.radius.md).fill(tokens.color(\.surfaceElevated))
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint.opacity(skin.opacity.o70))
            } else {
                AinkradSpinner()
            }
        }
    }

    // MARK: - MCP required secrets

    /// The secret KEY NAMES this MCP server needs — never values. Shown as
    /// chips so the user knows what to add in the MCP manager before
    /// enabling it there; values are entered in Settings → MCP Servers, not here.
    private func requiredSecretsRow(_ keys: [String]) -> some View {
        HStack(spacing: skin.spacing.sm) {
            ForEach(keys, id: \.self) { key in
                AinkradChip(label: key, systemName: "key.fill")
            }
        }
    }

    // MARK: - Links

    private func linksRow(_ links: [ManifestLink]) -> some View {
        HStack(spacing: skin.spacing.lg) {
            ForEach(links, id: \.url) { link in
                Link(destination: link.url) {
                    AinkradChip(label: link.title, systemName: "arrow.up.right")
                }
            }
        }
    }
}
