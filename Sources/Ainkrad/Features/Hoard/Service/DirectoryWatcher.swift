import CoreServices
import Foundation

/// The only thing that crosses the FSEvents C-callback boundary. The watcher
/// itself is NOT `Sendable` (it owns a stream pointer), so handing *it* to the
/// callback trips Swift 6's region isolation. A box holding just the closure
/// is safely sendable, and it is what the context pointer carries.
// `@unchecked` is safe: the box is immutable (one `let`, written once in `init`
// before the pointer is shared) and the closure it holds is `@Sendable`.
private final class WatcherCallbackBox: @unchecked Sendable {
    let onChange: @Sendable @MainActor () -> Void
    init(_ onChange: @escaping @Sendable @MainActor () -> Void) {
        self.onChange = onChange
    }
}

/// Watches ONE directory and calls back on change. Non-recursive in effect:
/// FSEvents reports the subtree, but the callback only ever triggers a reload
/// of the directory the tab is showing, so deep churn costs one listing.
///
/// A class with manual lifecycle rather than an `AsyncStream`, because the
/// FSEvents C API wants a stable context pointer and an explicit invalidate.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    /// Retained for the stream's lifetime and released in `stop()` — ARC
    /// cannot see the reference FSEvents holds through the context pointer.
    private var boxPointer: UnsafeMutableRawPointer?

    init(url: URL, onChange: @escaping @Sendable @MainActor () -> Void) {
        let box = WatcherCallbackBox(onChange)
        let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        boxPointer = pointer

        var streamContext = FSEventStreamContext(
            version: 0, info: pointer, retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            // Only the closure crosses the isolation boundary, never the
            // watcher — that is the whole point of the box.
            let handler = Unmanaged<WatcherCallbackBox>.fromOpaque(info)
                .takeUnretainedValue().onChange
            Task { @MainActor in handler() }
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &streamContext,
            [url.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            // 200ms coalescing: a `git checkout` or an unzip fires hundreds of
            // events, and re-listing per event would thrash the pane.
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    /// Idempotent: calling it twice, or after `deinit` has run, is a no-op.
    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let boxPointer {
            Unmanaged<WatcherCallbackBox>.fromOpaque(boxPointer).release()
            self.boxPointer = nil
        }
    }

    deinit {
        // `stop()` is the supported path; this is the safety net for a watcher
        // dropped without it. Inlined rather than calling `stop()` so `deinit`
        // touches no isolated state.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        if let boxPointer {
            Unmanaged<WatcherCallbackBox>.fromOpaque(boxPointer).release()
        }
    }
}
