import Foundation

/// Re-registration helper shared by bootstrap and the watcher: unregisters the
/// `previous` custom names, then registers the store's current `slashCommands()`
/// into `registry`. Returns the new live name set for the next resync. Never
/// touches a builtin — it only removes names it itself previously registered.
///
/// Precedence: builtins > skill commands > custom commands (absolute). `previous`
/// only ever contains names THIS function registered on an earlier call, so
/// unregistering them first is always safe. After that unregister pass, `taken`
/// is snapshotted from the registry's current contents (builtins + skills +
/// anything else already live) — a custom command whose name is already `taken`
/// is skipped entirely rather than overwriting it, and never enters the
/// returned live set, so a later resync can't unregister a skill/builtin name
/// it never actually owned.
@MainActor
func resyncCustomCommands(
    store: CustomCommandStore,
    registry: CommandRegistry,
    previous: Set<String>
) -> Set<String> {
    for name in previous { registry.unregister(name: name) }
    let taken = Set(registry.all().map(\.name))
    var live: Set<String> = []
    for command in store.slashCommands() where !taken.contains(command.name) {
        registry.register(command)
        live.insert(command.name)
    }
    return live
}

/// Watches a custom-command directory so a user adding/editing/removing a
/// `*.md` command is picked up without a relaunch. Modeled on `SkillWatcher`:
/// a `DispatchSourceFileSystemObject` on the dir fd, debounced so an editor's
/// atomic save (write+rename) coalesces to a single `onChange`. `start()`/
/// `stop()` are idempotent; the cancel handler closes the fd.
@MainActor
final class CustomCommandWatcher {
    private let directory: URL
    private let onChange: @MainActor () -> Void
    private let debounceInterval: Duration
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    init(
        directory: URL, debounceInterval: Duration = .milliseconds(200),
        onChange: @escaping @MainActor () -> Void
    ) {
        self.directory = directory
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        debounceTask?.cancel()
        source?.cancel()
    }

    func start() {
        guard source == nil else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let opened = open(directory.path, O_EVTONLY)
        guard opened >= 0 else { return }
        fd = opened
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened, eventMask: [.write, .rename, .delete], queue: .main)
        newSource.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        newSource.setCancelHandler { [weak self] in
            MainActor.assumeIsolated {
                if let f = self?.fd, f >= 0 { close(f) }
                self?.fd = -1
            }
        }
        source = newSource
        newSource.resume()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    func simulateChange() { scheduleReload() }
    func waitForPendingReload() async { await debounceTask?.value }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
