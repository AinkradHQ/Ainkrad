import Foundation
import AinkradAppKit
import AinkradSignal

/// What the assistant can learn from the notification feed.
///
/// **Read-only, and structurally so.** It holds a `SignalCenter` but calls only
/// `page` and `search`; there is no emit path here and no mutation. Sage
/// answering "what failed today?" must not be able to change the answer.
///
/// ## Ordering, not recency
///
/// The summary puts failures and warnings first, then fills the remaining
/// budget with recent events. A recency-ordered dump answers the question
/// wrongly exactly when there is most to say: a hundred `info` rows arriving
/// after a build failure would push the failure out, and the assistant would
/// confidently report nothing wrong. Severity-first is the whole reason this
/// is not a straight `page(limit:)` call.
@MainActor
struct SageSignalContext {
    let center: SignalCenter

    /// A hard character budget. Context is a budget, not a dump — every
    /// character here is one the user's actual question does not get.
    static let summaryBudget = 3_000
    static let searchBudget = 6_000
    /// How far back the summary looks. Enough to cover "today" without paging
    /// the whole store on every turn.
    static let scanLimit = 120

    /// A one-line answer to "what has been noisy?".
    ///
    /// Deliberately a SINGLE line, and prepended rather than appended: it
    /// costs about eighty characters out of three thousand, and the events
    /// themselves are what the assistant needs — a health readout that pushed
    /// two failures out of the context would be worse than no readout at all.
    ///
    /// Empty when there is too little history to describe, for the same reason
    /// the panel says "not enough history yet": a read rate over four events
    /// describes noise, not behaviour.
    func healthLine(now: Date = Date()) -> String {
        let health = center.health(since: now.addingTimeInterval(-7 * 86_400))
        guard health.total >= Self.minimumHealthSample else { return "" }
        var parts = ["Last 7 days: \(health.total) notifications",
                     "\(Int((health.readRate * 100).rounded()))% read"]
        if let loudest = health.noisiest.first {
            parts.append("loudest \(loudest.kind) (\(loudest.count))")
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Matches the readout's own floor, so the two never disagree about
    /// whether there is enough history to talk about.
    static let minimumHealthSample = 5

    /// Recent notable events as plain text, or an empty string when there is
    /// nothing.
    ///
    /// Empty rather than "no notifications": an empty context contributes
    /// nothing, whereas a sentence saying the feed is empty spends budget
    /// asserting an absence the assistant did not ask about. `search` behaves
    /// the OPPOSITE way, and for a reason — see there.
    func summary() -> String {
        let events = center.page(filter: .init(), before: nil, limit: Self.scanLimit)
        guard !events.isEmpty else { return "" }

        let notable = Self.collapsingRepeats(
            events.filter { $0.severity == .failure || $0.severity == .warning })
        let rest = Self.collapsingRepeats(
            events.filter { $0.severity != .failure && $0.severity != .warning })

        var lines: [String] = []
        var budget = Self.summaryBudget
        for event in notable + rest {
            let line = Self.line(for: event.0, repeats: event.1)
            // Stop at the first line that does not fit rather than skipping it
            // and continuing: skipping would silently reorder by length, and a
            // long failure is exactly the one worth keeping.
            guard line.count + 1 <= budget else { break }
            lines.append(line)
            budget -= line.count + 1
        }
        // The health line goes FIRST and is counted against the same budget:
        // "what has been noisy this week" is context for everything below it,
        // and an uncounted line is a budget that quietly is not one.
        let health = healthLine()
        if !health.isEmpty, health.count + 1 <= budget {
            lines.insert(health, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// Full-text search over the feed, as text.
    ///
    /// Reports finding nothing EXPLICITLY, unlike `summary`. An empty string
    /// reads to a model as a tool that failed and invites it to answer from
    /// memory instead; "No notifications match" is a fact it can use.
    func search(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No search query was given." }

        // FTS indexes `title` and `body` ONLY — not `kind`. So a search for
        // "failed" found nothing on a real feed full of `sync.failed` rows
        // whose titles read "Could not sync…", which is the single most likely
        // thing an assistant would search for. Matching kinds here as well
        // fixes that without a schema migration; indexing `kind` in the FTS
        // table is the better eventual answer and is recorded as such.
        let byText = center.search(trimmed)
        let needle = trimmed.lowercased()
        let byKind = center.page(filter: .init(), before: nil, limit: Self.scanLimit)
            .filter { $0.kind.lowercased().contains(needle) }
        var seen = Set(byText.map(\.id))
        let matches = byText + byKind.filter { seen.insert($0.id).inserted }

        guard !matches.isEmpty else {
            return "No notifications match \"\(trimmed)\"."
        }

        var lines: [String] = []
        var budget = Self.searchBudget
        for event in matches {
            let line = Self.line(for: event)
            guard line.count + 1 <= budget else { break }
            lines.append(line)
            budget -= line.count + 1
        }
        if lines.count < matches.count {
            lines.append("(\(matches.count - lines.count) more matches not shown.)")
        }
        return lines.joined(separator: "\n")
    }

    /// Collapses runs of the same `(source, kind)` down to their most recent
    /// occurrence, tagged with how many there were.
    ///
    /// Found by running this against a real feed: seventeen near-identical
    /// "Could not sync" warnings from one mail account, hours apart, filled the
    /// entire budget. The store's own 60-second dedupe cannot help — these are
    /// genuinely separate events — but for answering "what failed today?" they
    /// are one fact, and spending the whole budget restating it would crowd
    /// out a failure from another app entirely.
    ///
    /// The count is kept rather than dropped: "17 times" is the most useful
    /// part of a recurring failure, and an assistant told only about the
    /// latest one would describe a persistent outage as a blip.
    private static func collapsingRepeats(_ events: [SignalEvent]) -> [(SignalEvent, Int)] {
        var order: [SignalSourceKindKey] = []
        var newest: [SignalSourceKindKey: SignalEvent] = [:]
        var counts: [SignalSourceKindKey: Int] = [:]
        for event in events {
            let key = SignalSourceKindKey(source: event.source, kind: event.kind)
            if newest[key] == nil {
                newest[key] = event
                order.append(key)
            } else if event.timestamp > newest[key]!.timestamp {
                newest[key] = event
            }
            counts[key, default: 0] += 1
        }
        return order.map { (newest[$0]!, counts[$0]!) }
    }

    /// One event as a line.
    ///
    /// Names the SOURCE, because "Build failed" alone does not say whose build,
    /// and an assistant that cannot attribute a failure cannot suggest anything
    /// useful about it. Uses the same `sourceLabel` the feed's own rows use, so
    /// the assistant and the UI never disagree about what an app is called.
    private static func line(for event: SignalEvent, repeats: Int = 1) -> String {
        let stamp = ISO8601DateFormatter.string(from: event.timestamp,
                                                timeZone: .current,
                                                formatOptions: [.withInternetDateTime])
        var line = "[\(stamp)] \(event.severity.rawValue.uppercased()) "
            + "\(SignalPresentation.sourceLabel(event.source)) — \(event.title)"
        if repeats > 1 {
            line += " (\(repeats)x)"
        }
        if let body = event.body, !body.isEmpty {
            // Newlines flattened: a multi-line body would make one event look
            // like several to a model reading line by line.
            line += ": " + body.replacingOccurrences(of: "\n", with: " ")
        }
        return line
    }
}

/// Groups a summary by the pair that makes two events "the same problem".
private struct SignalSourceKindKey: Hashable {
    let source: SignalSource
    let kind: String
}
