import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// One source's detail, opened in place under its row in the Sources list.
///
/// The same shape for every source, deliberately: one thing the user learns
/// once, instead of Host being a special case with two toggles while the apps
/// that actually generate the noise have none.
///
/// It is a plain stack of rows, NOT a set of `AinkradSettingsPanel`s: it is
/// already rendered inside one, and three bordered panels nested in a fourth
/// read as a rendering fault rather than a hierarchy.
///
/// Takes everything as parameters and reaches for no environment, so it renders
/// in a snapshot. `SignalFeedOverlayView`'s comment records what happens
/// otherwise — a view that reaches for the whole environment crashed the
/// snapshot runner, and the run then reported "passed" for the tests that had
/// already finished.
struct SourceNotificationSheet: View {
    let source: SignalSource
    let sourceName: String
    @Binding var rules: RoutingRules
    /// What this source has actually emitted. Empty is a legitimate state —
    /// a source can be configurable before it has ever spoken.
    var activity: [SignalKindActivity] = []

    @Environment(\.ainkradTheme) private var theme
    /// Closed by default. These are the controls a user touches once a year,
    /// and they used to sit above the kinds list — the thing the detail is
    /// actually opened for.
    @State private var showsFineTuning = false

    /// Wide enough for the longer of the two segment labels at its heaviest
    /// weight, so no row is clipped and none is ragged. Narrower since the
    /// labels became "Alert" and "Quiet" — 190 was sized for "Everything" and
    /// "Feed only", and left the column floating well clear of its rows.
    private static let kindPickerWidth: CGFloat = 124

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            kinds
            AinkradDisclosureGroup(title: "Fine tuning", isExpanded: $showsFineTuning) {
                fineTuning
            }
        }
        .padding(.top, AinkradSpacing.xs)
    }

    /// The centrepiece, and now the FIRST thing in the detail. Every kind this
    /// source has emitted, noisiest first, each with the same two-state control
    /// the source itself uses.
    ///
    /// The list is discovered from the feed, so a kind an app starts emitting
    /// tomorrow appears on its own. A hand-maintained list would go stale the
    /// first time that happened, and the user would be unable to silence the
    /// one thing actually bothering them.
    @ViewBuilder
    private var kinds: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.xs + 2) {
            AinkradCaption("What \(sourceName) tells you — noisiest first. Quiet keeps a "
                           + "kind in the feed without interrupting.")
            if activity.isEmpty {
                // A legitimate state, and worth naming: an empty space here
                // reads as a control that failed to load.
                AinkradCaption("Nothing recorded from \(sourceName) yet.")
            } else {
                ForEach(activity) { entry in
                    HStack(spacing: AinkradSpacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.kind)
                                .font(AinkradFont.mono(11))
                                .foregroundStyle(theme.foreground)
                            Text(entry.count == 1 ? "once" : "\(entry.count) times")
                                .font(AinkradFont.mono(9.5))
                                .foregroundStyle(theme.foreground.opacity(0.45))
                        }
                        Spacer(minLength: AinkradSpacing.sm)
                        AinkradSegmentedPicker(
                            items: SignalDeliveryMode.kindOptions,
                            selection: Binding(
                                get: { SignalDeliveryMode(rules: rules,
                                                          source: source, kind: entry.kind) },
                                set: { $0.apply(to: &rules, source: source, kind: entry.kind) }),
                            label: \.label)
                        // Fixed, because the control sizes to its content and
                        // the SELECTED segment is heavier — so an unconstrained
                        // column of these is ragged at both edges, with each
                        // row's width depending on what it happens to be set
                        // to. It reads as a rendering fault rather than a list.
                        .frame(width: Self.kindPickerWidth, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var fineTuning: some View {
        VStack(alignment: .leading, spacing: 9) {
            AinkradCaptionedRow("Interrupt me at") {
                AinkradSelect(
                    items: SignalSeverity.allCases,
                    selection: Binding(
                        get: { rules.interruptFloor[source] ?? .info },
                        set: { floor in
                            // `.info` is the absence of a floor, not a floor at
                            // the bottom: storing it would freeze an opinion
                            // where the user expressed none.
                            rules.interruptFloor[source] = floor == .info ? nil : floor
                        }),
                    label: { $0.floorLabel })
            }
            AinkradCaption("Below the floor, events go quiet — recorded, never "
                           + "interrupting.")
            AinkradCaptionedRow("Sound") {
                AinkradSelect(
                    items: SignalSoundChoice.offered,
                    selection: Binding(
                        get: { rules.soundOverride[source] ?? .bySeverity },
                        set: { choice in
                            rules.soundOverride[source] =
                                choice == .bySeverity ? nil : choice
                        }),
                    label: { $0.label })
            }
            AinkradCaptionedRow("Let urgent through quiet hours and Focus") {
                AinkradToggle(isOn: Binding(
                    get: { rules.urgentBypass.contains(source) },
                    set: { allowed in
                        if allowed { rules.urgentBypass.insert(source) }
                        else { rules.urgentBypass.remove(source) }
                    }))
            }
            AinkradCaption("Only events the app marks urgent — something waiting "
                           + "on you, not its usual chatter.")
        }
    }
}

private extension SignalSoundChoice {
    /// The cues offered today. `named` carries the host's own asset name, so
    /// this list grows when the notification cue family lands without the SDK
    /// needing to know any of them.
    static var offered: [SignalSoundChoice] {
        [.bySeverity, .silent, .named(UISound.confirm.rawValue),
         .named(UISound.error.rawValue)]
    }

    var label: String {
        switch self {
        case .bySeverity: return "Match severity"
        case .silent: return "Silent"
        case .named(let name):
            return UISound(rawValue: name)?.displayName ?? name
        // Resilient enum in a library-evolution module: a cue kind added to
        // the SDK later must render as something rather than failing to build.
        @unknown default:
            return "Match severity"
        }
    }
}
