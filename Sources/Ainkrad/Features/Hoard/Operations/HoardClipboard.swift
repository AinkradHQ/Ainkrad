import AppKit
import Foundation
import Observation

/// What a pending paste will do.
enum ClipboardIntent: Equatable, Sendable {
    case copy
    case cut
}

/// Ordinary ⌘C / ⌘X / ⌘V.
///
/// The original design leaned entirely on orthodox two-pane transfer (F5/F6),
/// which is a power-user idiom that only works when you already have two panes
/// open. Copy-and-paste is the idiom everyone actually has in their fingers,
/// works with one pane, reaches any destination, and — because it goes through
/// `NSPasteboard` — interoperates with the Finder and every other Mac app in
/// both directions.
///
/// The system pasteboard is the source of truth for the PATHS, so copying in
/// the Finder and pasting here works. Cut-versus-copy is tracked locally,
/// because macOS has no "cut file" pasteboard convention — the Finder itself
/// uses ⌘⌥V ("Move Items Here") for the same reason.
@MainActor
@Observable
final class HoardClipboard {
    private(set) var intent: ClipboardIntent = .copy
    /// URLs marked by the last ⌘X, so the list can dim them until pasted.
    private(set) var cutURLs: Set<URL> = []
    /// Bumped on every write so views re-evaluate `hasContents` — `NSPasteboard`
    /// is not observable, so nothing would otherwise tell SwiftUI to refresh.
    private(set) var generation = 0

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var hasContents: Bool {
        _ = generation
        return !urls().isEmpty
    }

    func copy(_ urls: [URL]) {
        write(urls, intent: .copy)
    }

    func cut(_ urls: [URL]) {
        write(urls, intent: .cut)
    }

    private func write(_ urls: [URL], intent: ClipboardIntent) {
        guard !urls.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        self.intent = intent
        cutURLs = intent == .cut ? Set(urls) : []
        generation += 1
    }

    /// URLs currently on the pasteboard — ours or another app's.
    func urls() -> [URL] {
        let objects =
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return objects ?? []
    }

    /// The operation a paste should perform. A cut only counts if the
    /// pasteboard still holds what WE cut — if another app has written since,
    /// this is somebody else's copy and moving their files would be wrong.
    func pendingOperation() -> (urls: [URL], isMove: Bool)? {
        let current = urls()
        guard !current.isEmpty else { return nil }
        let isMove = intent == .cut && Set(current) == cutURLs
        return (current, isMove)
    }

    /// Called after a successful paste of a cut: the files have moved, so the
    /// pasteboard no longer describes anything real.
    func clearAfterMove() {
        pasteboard.clearContents()
        cutURLs = []
        intent = .copy
        generation += 1
    }

    func isCut(_ url: URL) -> Bool {
        _ = generation
        return cutURLs.contains(url)
    }
}
