import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The Claude routes, as two explained CHOICES rather than a stack of
/// controls.
///
/// The previous version put an unlabelled icon-button, a primary button and
/// a pair of paste fields in one column with no indication that they were
/// alternatives to each other, and rendered any failure in a shared status
/// row far below — so a sign-in error appeared nowhere near the thing that
/// failed, under an unrelated section.
///
/// Each route now says what it does and what it costs the user (a browser
/// round trip, or nothing at all), and the failure lands inside this section
/// with the alternatives still on screen beside it.
///
/// Layout only: the async route actions stay in `SetupProvidersStepView`, which
/// owns their state, and arrive here as closures.
struct SetupClaudeRoutes: View {
    let tokens: AinkradSkin
    /// True when the importer says a Claude Code login exists on this Mac.
    let canImport: Bool
    let isBusy: Bool
    /// True while the loopback could not bind and the code must be pasted.
    let awaitingPaste: Bool
    let authorizeURL: URL?
    let routeError: String?
    @Binding var pasteText: String
    let onImport: () -> Void
    let onSignIn: () -> Void
    /// Handed the pasted text; the field is already cleared.
    let onPaste: (String) -> Void

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradSettingsPanel(
            title: "Claude subscription",
            hint: "Use a Claude Pro or Max plan you already pay for, instead of an API "
                + "key billed per token."
        ) {
            VStack(alignment: .leading, spacing: skin.spacing.md) {
                if canImport {
                    // Listed FIRST and marked as the quick one: it needs no browser
                    // and no typing, and it is the route that still works when the
                    // sign-in endpoint is refusing.
                    SetupClaudeRoute(
                        tokens: tokens,
                        icon: "arrow.down.doc.fill",
                        title: "Use your existing Claude Code login",
                        detail: "Found on this Mac. Nothing to type — reuses the login "
                            + "Claude Code already has.",
                        isRecommended: true,
                        isBusy: isBusy,
                        action: onImport)
                }

                SetupClaudeRoute(
                    tokens: tokens,
                    icon: "person.badge.key.fill",
                    title: "Sign in with Claude",
                    detail: "Opens your browser to approve Ainkrad, then comes back here.",
                    isRecommended: false,
                    isBusy: isBusy,
                    action: onSignIn)

                if awaitingPaste {
                    SetupPasteFallback(
                        tokens: tokens, authorizeURL: authorizeURL,
                        pasteText: $pasteText, onSubmit: onPaste)
                }

                // The failure belongs HERE, beside the routes it is about — not in a
                // shared status row under the API-key section.
                if let routeError {
                    SetupProviderStatusRow(
                        tokens: tokens, icon: "exclamationmark.triangle.fill",
                        text: routeError, color: tokens.color(\.accentTertiary)
                    )
                    .accessibilityIdentifier("setup.providers.routeError")
                }
            }
        }
    }
}

/// One Claude route: what it is, what it will do, and whether it is the easy
/// one. A whole-row button, so the target is the card rather than the words.
struct SetupClaudeRoute: View {
    let tokens: AinkradSkin
    let icon: String
    let title: String
    let detail: String
    let isRecommended: Bool
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.ainkradSkin) private var skin

    /// A raw `Button` on purpose: `AinkradListRow` holds one line of title and
    /// one of subtitle, and this card's detail wraps and carries a FASTEST tag.
    var body: some View {
        Button(action: action) {  // design-lint: allow raw-control kit gap, list row with multi-line detail
            HStack(alignment: .top, spacing: skin.size.s11) {
                Image(systemName: icon)
                    .font(skin.font(AinkradFontToken(sizeKey: "t15", scaled: false)))
                    .foregroundStyle(
                        isRecommended
                            ? tokens.color(\.accentSecondary)
                            : tokens.color(\.foreground).opacity(skin.opacity.o55)
                    )
                    .frame(width: skin.size.s20)
                VStack(alignment: .leading, spacing: skin.size.s3) {
                    HStack(spacing: skin.size.s7) {
                        Text(title)
                            .font(AinkradFont.display(13, weight: .medium))
                            .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o92))
                        if isRecommended {
                            Text("FASTEST")
                                .font(AinkradFont.display(9, weight: .medium)).kerning(0.6)
                                .foregroundStyle(tokens.color(\.accentSecondary))
                        }
                    }
                    Text(detail)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: skin.spacing.sm)
                if isBusy {
                    AinkradSpinner(size: skin.size.s16)
                } else {
                    Image(systemName: "chevron.right")
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", weight: "semibold", scaled: false)))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o30))
                }
            }
            .padding(skin.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferShape(cut: skin.radius.sm)
                    .fill(tokens.color(\.surfaceElevated).opacity(isRecommended ? skin.opacity.o62 : skin.opacity.o42))
            )
            .overlay(
                ChamferShape(cut: skin.radius.sm).strokeBorder(
                    isRecommended ? tokens.color(\.accentSecondary).opacity(skin.opacity.o30) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityHint(detail)
    }
}

/// Shown only when the loopback port could not bind, so the browser has
/// nowhere to redirect back to and the user has to carry the code across by
/// hand.
struct SetupPasteFallback: View {
    let tokens: AinkradSkin
    let authorizeURL: URL?
    @Binding var pasteText: String
    let onSubmit: (String) -> Void

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            Text("Paste the code from your browser")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o85))
            if let url = authorizeURL {
                // The loopback couldn't bind, so this URL is the only way back
                // to the consent screen if the tab was closed or
                // NSWorkspace.open failed.
                Link(destination: url) {
                    Text("Open the Claude sign-in page again")
                        .font(AinkradFont.display(11, weight: .medium))
                        .foregroundStyle(tokens.color(\.accentSecondary))
                }
            }
            HStack(spacing: skin.size.s10) {
                AinkradSecureField(text: $pasteText, placeholder: "Paste the redirect URL or code")
                AinkradIconButton(systemName: "checkmark.circle.fill", tooltip: "Submit the pasted code") {
                    let raw = pasteText
                    pasteText = ""
                    onSubmit(raw)
                }
                .accessibilityLabel("Submit the pasted code")
            }
        }
        .padding(skin.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: skin.radius.sm).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o50)))
    }
}

/// The API-key route: pick a preset, paste a key (and a base URL where the
/// preset allows one), and connect. The preset binding carries the parent's
/// reset rules, so switching provider behaves exactly as it does there.
struct SetupAPIKeyRoute: View {
    let tokens: AinkradSkin
    let preset: ProviderPreset
    /// Writing it switches preset — see `SetupProvidersStepView.presetSelection`.
    let presetSelection: Binding<String>
    @Binding var baseURL: String
    @Binding var token: String
    /// True when the SELECTED preset already has a saved connection.
    let isPresetConnected: Bool
    let isBusy: Bool
    let canConnect: Bool
    let onConnect: () -> Void

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradSettingsPanel(
            title: "API key",
            hint: "Paste a key for any supported provider — it's tested before it's saved."
        ) {
            AinkradSegmentedPicker(
                items: ProviderPreset.all.map(\.id),
                selection: presetSelection,
                label: { ProviderPreset.preset(id: $0).displayName }
            )
            .fixedSize()

            if preset.allowsBaseURLEdit {
                AinkradSecureField(text: $baseURL, placeholder: "Base URL")
            }

            // Says so when the SELECTED provider is already connected. Without
            // it, returning to a provider you connected five minutes ago shows
            // an empty key field and no acknowledgement — which reads as having
            // lost the connection.
            if isPresetConnected {
                HStack(spacing: skin.size.s7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                        .foregroundStyle(tokens.color(\.accentSecondary))
                    Text(
                        "\(preset.displayName) is connected. Enter a key below only to "
                            + "replace it."
                    )
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o60))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("setup.providers.presetConnected")
            }

            HStack(spacing: skin.size.s10) {
                if preset.requiresKey {
                    AinkradSecureField(text: $token, placeholder: "API key")
                } else {
                    Text("No API key required")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o45))
                }
                AinkradButton(
                    title: isPresetConnected ? "Replace" : "Connect",
                    style: .secondary, isLoading: isBusy,
                    action: onConnect
                )
                .disabled(isBusy || !canConnect)
            }
        }
    }
}
