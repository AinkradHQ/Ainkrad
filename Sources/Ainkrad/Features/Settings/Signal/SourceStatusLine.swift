import AinkradHostRuntime
import AinkradSignal

/// What a source's row says about itself beyond its Alert/Quiet/Off picker.
///
/// This replaces the standalone "Quiet and off" panel. That panel existed
/// because a mute the user cannot find is a bug they will report as
/// "notifications stopped working" — but it answered the question in the wrong
/// place, one screen below the control that produced the setting, and it
/// restated whole-source state the picker was already showing. Putting the
/// truth on the row means the diagnosis and the remedy are the same place,
/// which is the rule the feed's row menu already follows.
///
/// Deliberately silent about the source's own delivery mode: the picker
/// immediately to its left shows that, and saying it twice is what made three
/// controls disagree about one value.
enum SourceStatusLine {
    /// Nil when the source is entirely at its defaults — a row that says
    /// nothing extra is the common case, and filling it with "nothing
    /// overridden" would be furniture.
    static func text(rules: RoutingRules,
                     source: SignalSource,
                     loudest: SignalKindActivity? = nil) -> String? {
        var parts: [String] = []

        let quietKinds = rules.sourceKindOverrides
            .filter { $0.key.source == source && $0.value == [.feed] }
            .count
        if quietKinds > 0 {
            parts.append(quietKinds == 1 ? "1 kind quiet" : "\(quietKinds) kinds quiet")
        }

        if let floor = rules.interruptFloor[source] {
            parts.append(floor.floorSummary)
        }

        if let sound = rules.soundOverride[source] {
            switch sound {
            case .silent: parts.append("silent")
            case .named(let name): parts.append(UISound(rawValue: name)?.displayName ?? name)
            // Carried, but it is the default and says nothing.
            case .bySeverity: break
            @unknown default: break
            }
        }

        if rules.urgentBypass.contains(source) {
            parts.append("urgent bypasses Focus")
        }

        // The noisiest kind, but only where it is worth acting on. A source
        // whose loudest kind fired twice does not have a noise problem, and
        // labelling it as though it does trains the user to ignore this line.
        if let loudest, loudest.count >= Self.loudEnough {
            parts.append("loudest \(loudest.kind) ×\(loudest.count)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The point at which a kind is worth naming on the row. Below it the
    /// number describes an ordinary session rather than a source that is
    /// shouting.
    static let loudEnough = 5
}

extension SignalSeverity {
    /// Phrased as the floor it sets, not the severity it names — the row reads
    /// "Interrupt me at: anything", not "Interrupt me at: info".
    ///
    /// Internal rather than private to `SourceNotificationSheet`, because the
    /// status line has to describe the same setting in the same words: a floor
    /// that reads "Warnings and failures" in the control and something else on
    /// the row would look like two settings.
    var floorLabel: String {
        switch self {
        case .info: return "Anything"
        case .success: return "Success and above"
        case .warning: return "Warnings and failures"
        case .failure: return "Failures only"
        @unknown default: return "Anything"
        }
    }

    /// The same fact, lowercased for the middle of a status line.
    var floorSummary: String {
        switch self {
        case .info: return "anything interrupts"
        case .success: return "success and above"
        case .warning: return "warnings and failures"
        case .failure: return "failures only"
        @unknown default: return "anything interrupts"
        }
    }
}
