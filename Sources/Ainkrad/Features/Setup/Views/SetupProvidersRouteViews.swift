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
    let tokens: DesignTokens
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

    var body: some View {
        AinkradSettingsPanel(
            title: "Claude subscription",
            hint: "Use a Claude Pro or Max plan you already pay for, instead of an API "
                + "key billed per token."
        ) {
            VStack(alignment: .leading, spacing: 12) {
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
                        text: routeError, color: tokens.accentTertiary
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
    let tokens: DesignTokens
    let icon: String
    let title: String
    let detail: String
    let isRecommended: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(
                        isRecommended
                            ? tokens.accentSecondary
                            : tokens.foreground.opacity(0.55)
                    )
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(AinkradFont.display(13, weight: .medium))
                            .foregroundStyle(tokens.foreground.opacity(0.92))
                        if isRecommended {
                            Text("FASTEST")
                                .font(AinkradFont.display(9, weight: .medium)).kerning(0.6)
                                .foregroundStyle(tokens.accentSecondary)
                        }
                    }
                    Text(detail)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.foreground.opacity(0.3))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferShape(cut: AinkradRadius.sm)
                    .fill(tokens.surfaceElevated.opacity(isRecommended ? 0.62 : 0.42))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.sm).strokeBorder(
                    isRecommended ? tokens.accentSecondary.opacity(0.3) : .clear, lineWidth: 1)
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
    let tokens: DesignTokens
    let authorizeURL: URL?
    @Binding var pasteText: String
    let onSubmit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste the code from your browser")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            if let url = authorizeURL {
                // The loopback couldn't bind, so this URL is the only way back
                // to the consent screen if the tab was closed or
                // NSWorkspace.open failed.
                Link(destination: url) {
                    Text("Open the Claude sign-in page again")
                        .font(AinkradFont.display(11, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary)
                }
            }
            HStack(spacing: 10) {
                NeonSecureField(
                    text: $pasteText,
                    placeholder: "Paste the redirect URL or code",
                    tokens: tokens)
                Button {
                    let raw = pasteText
                    pasteText = ""
                    onSubmit(raw)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(tokens.accentSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Submit the pasted code")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.5)))
    }
}

/// The API-key route: pick a preset, paste a key (and a base URL where the
/// preset allows one), and connect. The preset binding carries the parent's
/// reset rules, so switching provider behaves exactly as it does there.
struct SetupAPIKeyRoute: View {
    let tokens: DesignTokens
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
                NeonSecureField(text: $baseURL, placeholder: "Base URL", tokens: tokens)
            }

            // Says so when the SELECTED provider is already connected. Without
            // it, returning to a provider you connected five minutes ago shows
            // an empty key field and no acknowledgement — which reads as having
            // lost the connection.
            if isPresetConnected {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.accentSecondary)
                    Text(
                        "\(preset.displayName) is connected. Enter a key below only to "
                            + "replace it."
                    )
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("setup.providers.presetConnected")
            }

            HStack(spacing: 10) {
                if preset.requiresKey {
                    NeonSecureField(text: $token, placeholder: "API key", tokens: tokens)
                } else {
                    Text("No API key required")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
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
