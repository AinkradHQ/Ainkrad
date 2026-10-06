import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// What the user has actually connected, listed.
///
/// This is the answer to the question the step could not previously answer:
/// connect OpenRouter, connect OpenAI, come back to OpenRouter, and nothing
/// on screen said the first one was still there. The routes below are about
/// ADDING a connection; this is the record of what exists, and it is read
/// from the store so it survives every switch, Back and return.
struct SetupConnectedList: View {
    let connections: [Connection]
    let tokens: DesignTokens
    let onRemove: (Connection) -> Void

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if !connections.isEmpty {
            AinkradSettingsPanel(
                title: "Connected",
                hint: "Providers you've already linked — remove one below to disconnect it."
            ) {
                VStack(alignment: .leading, spacing: skin.spacing.sm) {
                    ForEach(connections) { connection in
                        SetupConnectedRow(connection: connection, tokens: tokens) {
                            onRemove(connection)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Connected providers")
        }
    }
}

/// One saved connection in the Providers step's "Connected" list, with the
/// control that removes it.
struct SetupConnectedRow: View {
    let connection: Connection
    let tokens: DesignTokens
    let onRemove: () -> Void

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            Image(systemName: "checkmark.seal.fill")
                .font(skin.font(AinkradFontToken(sizeKey: "t13", scaled: false)))
                .foregroundStyle(tokens.accentSecondary)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(connection.displayName)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o92))
                // The host, not the whole URL: it identifies WHICH endpoint
                // without turning the row into a path nobody reads.
                Text(URL(string: connection.baseURL)?.host ?? connection.baseURL)
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "system", scaled: false)))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
            }
            Spacer(minLength: 0)
            AinkradIconButton(systemName: "trash", tooltip: "Remove this connection", action: onRemove)
                .accessibilityLabel("Remove \(connection.displayName)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An icon and a line of copy in the colour of what happened — a connection
/// made, a failure, a deferral.
struct SetupProviderStatusRow: View {
    let tokens: DesignTokens
    let icon: String
    let text: String
    let color: Color

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            Image(systemName: icon).font(skin.font(AinkradFontToken(sizeKey: "t13", scaled: false))).foregroundStyle(
                color)
            Text(text)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
