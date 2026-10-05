import Foundation

/// Watches the local `Skills/` directory so a user adding, editing, or removing
/// a `SKILL.md` is picked up without a relaunch — wires a
/// `DispatchSource.makeFileSystemObjectSource` on the directory's fd to
/// `SkillRegistry.reload()` (via the injected `onChange`).
///
/// A rapid burst of filesystem events (e.g. an editor's atomic-save
/// write+rename+delete sequence, or several files landing in one drop)
/// coalesces to a single reload: each event restarts a short debounce timer
/// rather than firing immediately, so `onChange` runs once per settled burst,
/// not once per event.
///
/// Lifecycle: `start()`/`stop()` are idempotent and safe to call in either
/// order, including without a preceding `start()`. `stop()` (and `deinit`)
/// cancel the pending debounce and the dispatch source; the source's cancel
/// handler closes the fd, so no descriptor is ever leaked. The watcher holds
/// no reference to `SkillRegistry` itself — only the caller-supplied
/// `onChange` closure — so callers typically capture the registry weakly to
/// avoid a retain cycle.
@MainActor
final class SkillWatcher {
    private let paths: SkillPaths
    private let onChange: @MainActor () -> Void
    private let debounceInterval: Duration

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    init(
        paths: SkillPaths,
        debounceInterval: Duration = .milliseconds(200),
        onChange: @escaping @MainActor () -> Void
    ) {
        self.paths = paths
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        // `stop()` is @MainActor-isolated and can't be called from a
        // (possibly non-isolated) deinit; tear the source/fd down directly —
        // cancelling the source's own cancel handler closes the fd.
        debounceTask?.cancel()
        source?.cancel()
    }

    /// Opens the directory fd and resumes the dispatch source. Creates the
    /// directory first if it doesn't exist yet (a fresh install has no
    /// `Skills/` folder until the first skill lands) so the source always has
    /// something to open. If the open still fails, the watcher simply does
    /// nothing — never crashes — matching the rest of the Skills subsystem's
    /// degrade-don't-crash posture.
    func start() {
        guard source == nil else { return }  // already running
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)

        let opened = open(paths.root.path, O_EVTONLY)
        guard opened >= 0 else { return }
        fd = opened

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        newSource.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        newSource.setCancelHandler { [weak self] in
            MainActor.assumeIsolated {
                if let openFD = self?.fd, openFD >= 0 { close(openFD) }
                self?.fd = -1
            }
        }
        source = newSource
        newSource.resume()
    }

    /// Cancels any pending debounce and the dispatch source (which closes the
    /// fd via its cancel handler). Idempotent — safe to call repeatedly, or
    /// without a preceding `start()`.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    /// Test-only hook: invokes the same coalescing path a real fd event would
    /// take, without depending on kernel FS-event timing.
    func simulateChange() {
        scheduleReload()
    }

    /// Test-only hook: awaits the in-flight debounce task (if any) so a test
    /// can assert on `onChange` having fired, deterministically rather than
    /// via a sleep-and-hope guess at the debounce window.
    func waitForPendingReload() async {
        await debounceTask?.value
    }

    /// Restarts the debounce timer on every call, so a burst of events
    /// collapses to one `onChange` fired `debounceInterval` after the last
    /// event in the burst settles.
    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
