import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// One catalog/app card: icon, name, version line, description, and a trailing
/// action area driven by `row.status` + whether it is busy. Tapping the
/// icon/name/description area opens the app's detail page (AIN-147); the
/// actions row below is excluded so Install/Update/Uninstall/enable taps
/// don't also trigger navigation. The actions themselves live in the shared
/// `AppStoreActionControls` (AIN-149) so the grid card and the detail page
/// never diverge. The chamfer, hover glow, and border-brighten (skipped
/// under Reduce Motion) all come from `AinkradCard` — this view only wires
/// the open-vs-actions hit split on top of it: `AinkradCard`'s own `onTap`
/// is left `nil` so the whole card never routes taps, and `onOpen` is
/// attached only to the content sub-area above the actions row.
struct AppStoreCard: View {
    let row: AppStoreRow
    let tokens: DesignTokens
    let isBusy: Bool
    let onOpen: () -> Void
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onToggleEnabled: (Bool) -> Void

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    HStack(spacing: skin.spacing.md) {
                        AinkradAppTile(symbol: row.icon, size: skin.size.s42)
                        VStack(alignment: .leading, spacing: skin.size.s1) {
                            Text(row.displayName)
                                .font(AinkradFont.display(13, weight: .medium))
                                .foregroundStyle(tokens.foreground)
                            Text(row.versionLine)
                                .font(skin.font(AinkradFontToken(sizeKey: "t10", scaled: false)))
                                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
                        }
                        Spacer()
                        if row.status == .updateAvailable {
                            AinkradBadge(text: "UPDATE", status: .warning)
                        } else if row.kind == .mcpServer {
                            AinkradBadge(text: "MCP", status: .success)
                        } else if isDevPlugin {
                            AinkradBadge(text: "DEV", status: .neutral)
                        }
                    }

                    // Reserve two lines so every card is the same height
                    // regardless of description length (uniform grid).
                    Text(row.description.isEmpty ? " " : row.description)
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o70))
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                Spacer(minLength: 0)  // pin the action row to the card bottom

                AppStoreActionControls(
                    row: row, tokens: tokens, isBusy: isBusy,
                    onInstall: onInstall, onUpdate: onUpdate, onUninstall: onUninstall, onToggleEnabled: onToggleEnabled
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: AppStoreCard.cardHeight)
    }

    /// Fixed card height so the grid reads as a uniform matrix — content that
    /// varies (short vs 2-line descriptions, button vs "Installed" label) no
    /// longer changes a card's size.
    static let cardHeight: CGFloat = 150

    /// A registered plugin that the App Store didn't install (loaded from
    /// DevPlugins) — present and toggleable, but not uninstallable here.
    private var isDevPlugin: Bool {
        row.kind == .plugin && row.status != .available && !row.isManaged
    }
}
