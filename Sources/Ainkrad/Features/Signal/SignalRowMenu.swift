import AppKit
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// The right-click menu on a feed row.
///
/// This is the shortest path from noticing noise to stopping it. Everything
/// here is reachable from Settings too, but a user who has just been
/// interrupted by the nineteenth identical warning is not in Settings — they
/// are looking at the row, and asking them to go elsewhere is asking them to
/// leave the problem behind in order to solve it.
@MainActor
enum SignalRowMenu {
    static func items(for event: SignalEvent,
                      rules: RoutingRules,
                      sourceName: String,
                      isRead: Bool,
                      isPinned: Bool,
                      onMuteKind: @escaping () -> Void,
                      onUnmuteKind: @escaping () -> Void,
                      onMuteSource: @escaping () -> Void,
                      onToggleRead: @escaping () -> Void,
                      onCopy: @escaping () -> Void,
                      onDismiss: @escaping () -> Void,
                      onTogglePin: @escaping () -> Void) -> [AinkradMenuItem] {
        var items: [AinkradMenuItem] = []

        items.append(AinkradMenuItem(title: isRead ? "Mark as unread" : "Mark as read",
                                     systemName: isRead ? "envelope.badge" : "envelope.open",
                                     action: onToggleRead))
        // Above Dismiss deliberately: they are opposites, and the destructive
        // one should not be the first thing under the cursor.
        items.append(AinkradMenuItem(title: isPinned ? "Unpin" : "Pin",
                                     systemName: isPinned ? "pin.slash" : "pin",
                                     action: onTogglePin))
        items.append(AinkradMenuItem(title: "Copy", systemName: "doc.on.doc",
                                     action: onCopy))
        // Not confirmed. It is one row out of a log that already evicts by
        // age and by count — a dialog here would treat the feed as a filing
        // system rather than a record of what happened.
        items.append(AinkradMenuItem(title: "Dismiss", systemName: "xmark",
                                     action: onDismiss))

        // Named, not generic. "Quiet this" tells the user nothing about what
        // will go quiet; naming the source and the kind is the difference
        // between a control they trust and one they avoid.
        //
        // The verbs are the three delivery states — Alert, Quiet, Off — and
        // nothing else. This menu previously spoke a private dialect (mute,
        // unmute, mute everything) that matched no control in Settings, so the
        // user had no way to tell that the row menu and the delivery picker
        // were the same setting.
        let isKindQuiet = rules.sourceKindOverrides[
            SourceKind(source: event.source, kind: event.kind)] == [.feed]
        if isKindQuiet {
            items.append(AinkradMenuItem(title: "Alert me about \(sourceName) › \(event.kind)",
                                         systemName: "bell",
                                         action: onUnmuteKind))
        } else {
            items.append(AinkradMenuItem(title: "Quiet \(sourceName) › \(event.kind)",
                                         systemName: "bell.slash",
                                         action: onMuteKind))
        }

        // Turning a whole source off is a bigger step, so it is marked
        // destructive — not because it deletes anything, but because it is the
        // item most likely to be regretted, and the styling is the only warning
        // a menu can give.
        if !rules.mutedSources.contains(event.source) {
            items.append(AinkradMenuItem(title: "Turn off everything from \(sourceName)",
                                         systemName: "bell.slash.fill",
                                         isDestructive: true,
                                         action: onMuteSource))
        }
        return items
    }

    /// Plain text, because the point is pasting a build error into a chat.
    static func clipboardText(for event: SignalEvent,
                              sourceName: String,
                              formatter: DateFormatter) -> String {
        var lines = ["[\(formatter.string(from: event.timestamp))] \(sourceName) · \(event.kind)",
                     event.title]
        if let body = event.body, !body.isEmpty { lines.append(body) }
        return lines.joined(separator: "\n")
    }
}
