import Foundation
import AinkradSignal

/// How the user last left the feed.
///
/// Persisted because the alternative is rebuilding the same filter every time:
/// the two views anyone actually wants — "just the failures" and "just this
/// app" — take three clicks each, and having to redo them is what teaches
/// people to stop filtering at all.
struct SignalViewState: Codable, Equatable {
    enum Grouping: String, Codable { case byTime, bySource }

    var grouping: Grouping
    /// Nil is "All".
    var selectedSource: SignalSource?
    var severities: Set<SignalSeverity>
    var unreadOnly: Bool
    var collapsedSources: Set<String>

    init(grouping: Grouping = .byTime,
         selectedSource: SignalSource? = nil,
         severities: Set<SignalSeverity> = [],
         unreadOnly: Bool = false,
         collapsedSources: Set<String> = []) {
        self.grouping = grouping
        self.selectedSource = selectedSource
        self.severities = severities
        self.unreadOnly = unreadOnly
        self.collapsedSources = collapsedSources
    }

    /// Tolerant, like every other stored shape here: an unknown or missing
    /// field must leave the rest intact rather than reset the whole view.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grouping = try c.decodeIfPresent(Grouping.self, forKey: .grouping) ?? .byTime
        selectedSource = try c.decodeIfPresent(SignalSource.self, forKey: .selectedSource)
        severities = try c.decodeIfPresent(Set<SignalSeverity>.self, forKey: .severities) ?? []
        unreadOnly = try c.decodeIfPresent(Bool.self, forKey: .unreadOnly) ?? false
        collapsedSources = try c.decodeIfPresent(
            Set<String>.self, forKey: .collapsedSources) ?? []
    }

    /// The two views the user would otherwise rebuild by hand every time. Two,
    /// deliberately — a saved-view editor is a feature nobody has asked for.
    static let failures = SignalViewState(severities: [.failure], unreadOnly: true)

    var isShowingEverything: Bool {
        selectedSource == nil && severities.isEmpty && !unreadOnly
    }

    /// How many of the CHIP filters are on. The rail's source selection is
    /// deliberately excluded: it has its own always-visible control, and
    /// counting it would make the Filters button claim a filter the user can
    /// already see is set.
    var chipFilterCount: Int {
        severities.count + (unreadOnly ? 1 : 0)
    }

    /// Whether grouping by app can say anything. With one source selected every
    /// event is from that source, so the grouped list is a single group with a
    /// header naming what the rail already names — the state that made two
    /// controls answer one question.
    var canGroupBySource: Bool { selectedSource == nil }

    /// What the list should actually do, as opposed to what is stored. Stored
    /// grouping survives selecting a source and comes back when the user
    /// returns to All, rather than being silently rewritten.
    var effectiveGrouping: Grouping {
        canGroupBySource ? grouping : .byTime
    }

    /// The store filter this view describes. Grouping and collapse are
    /// presentation only and deliberately absent.
    var filter: SignalFilter {
        SignalFilter(sources: selectedSource.map { [$0] },
                     severities: severities.isEmpty ? nil : severities,
                     unreadOnly: unreadOnly)
    }
}

/// JSON beside the preferences. Separate from `SignalPreferences` because this
/// is where the user was looking, not what they decided — losing it is a minor
/// annoyance, and it must never be able to corrupt a routing rule.
struct SignalViewStateStore {
    let url: URL

    func load() -> SignalViewState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SignalViewState.self, from: data)
        else { return SignalViewState() }
        return state
    }

    func save(_ state: SignalViewState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.persistence.error("Failed to write \(data.count, privacy: .public) bytes to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
