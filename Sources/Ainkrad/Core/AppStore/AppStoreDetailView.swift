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
    let tokens: DesignTokens
    let isBusy: Bool
    let onBack: () -> Void
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void
    /// Opens the full-screen lightbox on the tapped screenshot (gallery, index).
    let onOpenScreenshot: ([URL], Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                backButton
                header
                VStack(alignment: .leading, spacing: 8) {
                    AinkradSectionHeader(title: "Description")
                    Text(longDescriptionText)
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.foreground.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(informationLine)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                if let secretKeys = requiredSecretKeys {
                    VStack(alignment: .leading, spacing: 8) {
                        AinkradSectionHeader(title: "Requires Secrets")
                        requiredSecretsRow(secretKeys)
                    }
                }
                if let screenshots = entry?.screenshots, !screenshots.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        AinkradSectionHeader(title: "Screenshots")
                        screenshotGallery(screenshots)
                    }
                }
                if let links = entry?.links, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        AinkradSectionHeader(title: "Links")
                        linksRow(links)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var backButton: some View {
        HStack(spacing: 8) {
            AinkradIconButton(systemName: "chevron.left", action: onBack)
            Text("Back")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.7))
        }
        .help("Back to catalog")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            NeonAppTile(symbol: row.icon, tokens: tokens, size: 88)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.displayName)
                    .font(AinkradFont.display(20, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                if let author = entry?.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                Text(row.versionLine)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                actions.padding(.top, 4)
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
        if let author = entry?.author, !author.isEmpty { parts.append(author) }
        parts.append(kindLabel)
        return parts.joined(separator: " · ")
    }

    /// The shared Install/Update/Enable/Disable/Uninstall controls (AIN-149)
    /// — identical to `AppStoreCard`'s, just rendered at the `.detail`
    /// size that fits the detail header.
    private var actions: some View {
        AppStoreActionControls(
            row: row, tokens: tokens, isBusy: isBusy, style: .detail,
            onInstall: onInstall, onUpdate: onUpdate, onUninstall: onUninstall, onToggleEnabled: onToggleEnabled)
    }

    // MARK: - Screenshot gallery

    private func screenshotGallery(_ urls: [URL]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
                screenshotBox(systemImage: "exclamationmark.triangle", tint: tokens.accentTertiary)
            default:
                screenshotBox(systemImage: nil, tint: tokens.foreground)
            }
        }
        .frame(width: 260, height: 164)
        .clipShape(ChamferShape(cut: AinkradRadius.md))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.foreground.opacity(0.1), lineWidth: 1))
        .contentShape(ChamferShape(cut: AinkradRadius.md))
        .onTapGesture { onOpenScreenshot(urls, index) }
        .help("View full size")
    }

    private func screenshotBox(systemImage: String?, tint: Color) -> some View {
        ZStack {
            ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated)
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint.opacity(0.7))
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
        HStack(spacing: 8) {
            ForEach(keys, id: \.self) { key in
                AinkradChip(label: key, systemName: "key.fill")
            }
        }
    }

    // MARK: - Links

    private func linksRow(_ links: [ManifestLink]) -> some View {
        HStack(spacing: 16) {
            ForEach(links, id: \.url) { link in
                Link(destination: link.url) {
                    AinkradChip(label: link.title, systemName: "arrow.up.right")
                }
            }
        }
    }
}
