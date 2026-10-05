import CoreServices
import Foundation

enum GlobMatcher {
    /// nil glob = match any path; else fnmatch the last path component.
    static func matches(_ path: String, glob: String?) -> Bool {
        guard let glob else { return true }
        let base = (path as NSString).lastPathComponent
        return fnmatch(glob, base, 0) == 0
    }
}

/// Watches a path subtree via FSEvents and emits debounced, glob-filtered
/// TriggerEvents. Also used for git-refs watching (point at `<repo>/.git`).
@MainActor
final class FileChangeWatcher {
    private let debounceInterval: TimeInterval
    private var streams: [FSEventStreamRef] = []
    private var debouncers: [UUID: Debouncer] = [:]

    init(debounceInterval: TimeInterval = 1) { self.debounceInterval = debounceInterval }

    func watch(
        scheduleID: UUID, path: String, glob: String?,
        onChange: @escaping @MainActor (TriggerEvent) -> Void
    ) {
        let debouncer = Debouncer(interval: debounceInterval)
        debouncers[scheduleID] = debouncer

        // The FSEvents C callback hops back to the main actor, filters by glob,
        // and debounces before emitting a single coalesced event.
        final class Context {
            let handler: (Set<String>) -> Void
            init(_ h: @escaping (Set<String>) -> Void) { handler = h }
        }
        let ctxObject = Context { changed in
            let matching = changed.filter { GlobMatcher.matches($0, glob: glob) }
            guard !matching.isEmpty else { return }
            debouncer.schedule {
                onChange(TriggerEvent(scheduleID: scheduleID, payload: matching.sorted().joined(separator: ", ")))
            }
        }
        let unmanaged = Unmanaged.passRetained(ctxObject)
        var context = FSEventStreamContext(
            version: 0, info: unmanaged.toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<Context>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let ctx = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
            let cPaths = unsafeBitCast(paths, to: UnsafePointer<UnsafePointer<CChar>>.self)
            var changed = Set<String>()
            for i in 0..<count { changed.insert(String(cString: cPaths[i])) }
            let snapshot = changed
            Task { @MainActor in ctx.handler(snapshot) }
        }
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        else {
            unmanaged.release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        streams.append(stream)
    }

    /// Registers a git-refs trigger: watches `<repoPath>/.git` for any change
    /// (glob nil) so ref updates (checkout, commit, merge) fire the schedule.
    /// PROVISIONAL: if a native Git Mage change-event seam exists, prefer
    /// subscribing to it instead of polling `.git` via FSEvents.
    func watchGitChange(
        scheduleID: UUID, repoPath: String,
        onChange: @escaping @MainActor (TriggerEvent) -> Void
    ) {
        watch(scheduleID: scheduleID, path: repoPath + "/.git", glob: nil, onChange: onChange)
    }

    func stopAll() {
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
        debouncers.removeAll()
    }
}
