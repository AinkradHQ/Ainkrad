import AinkradSignal

/// The three states a source's delivery can be in, as the user sees them.
///
/// `RoutingRules` can express far more than three states — per-channel sets and
/// per-kind overrides both live there — but three is what a settings row can
/// carry without becoming a control panel. The full model is a later phase; this
/// exists so the mapping between what is shown and what is stored is ONE tested
/// function rather than conditionals spread across a view.
enum SignalDeliveryMode: String, CaseIterable, Identifiable {
    /// Follows the severity and importance table, as an unconfigured source does.
    case everything
    /// Recorded, never surfaced.
    case feedOnly
    /// Muted. Still recorded — the log is not optional.
    case off

    var id: String { rawValue }

    /// One ladder, three words, spoken the same way by every surface — the
    /// picker, the row menu, the summary badges, the health panel.
    ///
    /// "Feed only" named the MECHANISM, which is why every control that could
    /// silence something had to carry a hint explaining that the feed still
    /// gets it. "Quiet" names what the user gets — there, not shouting — and
    /// the hint reduces to one line at the top of the pane.
    var label: String {
        switch self {
        case .everything: return "Alert"
        case .feedOnly: return "Quiet"
        case .off: return "Off"
        }
    }

    /// Reads the mode back out of the rules.
    ///
    /// Mute is checked first because `route` checks it first: a muted source
    /// stops at the feed whatever else is set, so showing anything but "Off"
    /// would misdescribe the behaviour.
    ///
    /// A channel set this enum cannot express — which only a later phase's
    /// controls can produce — reads as `.everything`. That is honest about what
    /// the row can show, and because `.everything` writes nothing unless the
    /// user actually picks it, merely looking at the row cannot destroy the
    /// richer setting.
    init(rules: RoutingRules, source: SignalSource) {
        if rules.mutedSources.contains(source) { self = .off }
        else if rules.sourceOverrides[source] == [.feed] { self = .feedOnly }
        else { self = .everything }
    }

    /// Writes the mode into the rules, clearing whatever the other two modes
    /// would have left behind.
    func apply(to rules: inout RoutingRules, source: SignalSource) {
        rules.mutedSources.remove(source)
        rules.sourceOverrides[source] = nil
        switch self {
        case .everything:
            // Deliberately stores NOTHING. Writing today's full channel set
            // would freeze today's severity table into the user's preferences
            // file, so a later improvement to the defaults would never reach
            // anyone who had ever opened this row.
            break
        case .feedOnly:
            rules.sourceOverrides[source] = [.feed]
        case .off:
            rules.mutedSources.insert(source)
        }
    }

    // MARK: - per kind

    /// The states a single KIND can be in — two, not three.
    ///
    /// `mutedSources` is per SOURCE and has no per-kind equivalent, so the
    /// strongest thing that can be said about one kind is "recorded, never
    /// surfaced". `.off` would therefore be indistinguishable from `.feedOnly`
    /// and the control would have an option it could never display — a dead
    /// third segment. `kindOptions` is what the picker offers.
    static let kindOptions: [SignalDeliveryMode] = [.everything, .feedOnly]

    init(rules: RoutingRules, source: SignalSource, kind: String) {
        let key = SourceKind(source: source, kind: kind)
        self = rules.sourceKindOverrides[key] == [.feed] ? .feedOnly : .everything
    }

    /// Writes a per-kind setting. `.off` is accepted and stored as feed-only,
    /// so a caller that passes it gets the strongest available behaviour rather
    /// than an error — but the picker offers `kindOptions`, which excludes it.
    func apply(to rules: inout RoutingRules, source: SignalSource, kind: String) {
        let key = SourceKind(source: source, kind: kind)
        switch self {
        case .everything: rules.sourceKindOverrides[key] = nil
        case .feedOnly, .off: rules.sourceKindOverrides[key] = [.feed]
        }
    }
}
