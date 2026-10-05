import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Settings → Sound: the sound-effects master toggle + volume (AIN-108) and
/// per-event cue configuration. Split out of General into its own section so
/// each surface stays focused. Bound to `GeneralSettingsStore`, persisted
/// immediately with no Save button — same pattern as the other sections.
struct SoundSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.generalSettingsStore

        return VStack(alignment: .leading, spacing: 16) {
            AinkradSettingsPanel(
                title: "Sound",
                hint: "Workspace interaction sounds."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    row(
                        tokens: tokens,
                        title: "Sound effects",
                        subtitle: "Plays a short chime on HUD open/close, install, and other key actions.",
                        isOn: store.soundEnabled,
                        action: { store.setSoundEnabled($0) })

                    if store.soundEnabled {
                        volumeRow(tokens: tokens, store: store)
                    }
                }
            }

            if store.soundEnabled {
                AinkradSettingsPanel(
                    title: "Sound effects",
                    hint:
                        "Enable each cue individually and choose which effect it plays. ▶ previews the selected effect."
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(UISound.allCases) { event in
                            soundEventRow(tokens: tokens, store: store, event: event)
                        }
                    }
                }
            }
        }
    }

    /// One per-event row: name + when-it-fires, an effect chooser, a preview
    /// button, and the enable toggle. Disabled events keep their chooser
    /// visible (dimmed) so a user can re-pick before re-enabling.
    private func soundEventRow(tokens: DesignTokens, store: GeneralSettingsStore, event: UISound) -> some View {
        let isOn = store.isEventEnabled(event)
        let chosen = store.effect(for: event)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayName)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isOn ? 0.9 : 0.45))
                Text(event.eventDescription)
                    .font(AinkradFont.display(10))
                    .foregroundStyle(tokens.foreground.opacity(isOn ? 0.45 : 0.3))
            }

            Spacer(minLength: 12)

            // Effect chooser as a HUD popover. The custom binding preserves both
            // the store write-back AND the on-change preview side-effect that the
            // native menu fired per item tap (AinkradSelect is a pure Binding<T>).
            AinkradSelect(
                items: UISound.allCases,
                selection: Binding(
                    get: { chosen },
                    set: { newEffect in
                        store.setEffect(newEffect, for: event)
                        environment.sounds.preview(newEffect)
                    }
                ),
                label: { effectLabel($0, for: event) }
            )
            .fixedSize()
            .opacity(isOn ? 1 : 0.55)

            Button {
                environment.sounds.preview(chosen)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(tokens.accentSecondary.opacity(isOn ? 0.9 : 0.5))
            }
            .buttonStyle(.plain)
            .help("Preview")

            AinkradToggle(isOn: Binding(get: { isOn }, set: { store.setEventEnabled($0, for: event) }))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    /// Chooser labels: the event's own sound reads as "Default (name)" so the
    /// out-of-the-box mapping is recognizable at a glance.
    private func effectLabel(_ effect: UISound, for event: UISound) -> String {
        effect == event ? "Default (\(effect.displayName))" : effect.displayName
    }

    private func volumeRow(tokens: DesignTokens, store: GeneralSettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                AinkradSlider(
                    value: Binding(
                        get: { store.soundVolume },
                        set: { store.setSoundVolume($0) }
                    ),
                    in: 0...1
                )
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    private func row(
        tokens: DesignTokens, title: String, subtitle: String,
        isOn: Bool, action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text(subtitle)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            Spacer(minLength: 12)
            AinkradToggle(isOn: Binding(get: { isOn }, set: action))
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }
}
