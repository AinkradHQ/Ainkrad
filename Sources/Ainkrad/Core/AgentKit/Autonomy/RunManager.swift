import Foundation
import Observation
import AinkradHostRuntime

/// The `@Observable` engine that owns `AgentRun`s end-to-end: a queue, a
/// bounded active/running set, terminal history, pause/stop, best-effort
/// completion notification, and relaunch recovery (persisted runs surviving
/// an app restart can never still be "running" — the process that ran them
/// is gone).
@MainActor
@Observable
final class RunManager {
    private var document: AgentRunsDocument
    private let persistence: PersistenceStore
    private let runner: AgentRunRunner
    /// The notification feed. A completed run's banner comes from here: the
    /// separate run notifier that used to own it is gone, along with the routing
    /// exemption that kept the two from posting twice.
    private weak var signalCenter: SignalCenter?
    private let maxConcurrent: Int
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(persistence: PersistenceStore, runner: AgentRunRunner,
         signalCenter: SignalCenter? = nil, maxConcurrent: Int = 2) {
        self.persistence = persistence
        self.runner = runner
        self.signalCenter = signalCenter
        self.maxConcurrent = max(1, maxConcurrent)
        self.document = persistence.load(AgentRunsDocument.self) ?? AgentRunsDocument()

        // Relaunch recovery: a run persisted as `.running` never got to finish —
        // the process that was running it is gone. Reclassify it to a terminal
        // state so it never holds a phantom concurrency slot. Queued/paused runs
        // are left as-is: they never held a slot, so they're safely re-queueable
        // (and `pump()` below will pick queued ones back up).
        for i in document.runs.indices where document.runs[i].status == .running {
            document.runs[i].status = .interrupted
            document.runs[i].finishedAt = Date()
        }
        save()
        pump()
    }

    /// Newest first.
    var runs: [AgentRun] { document.runs.sorted { $0.createdAt > $1.createdAt } }
    var active: [AgentRun] { runs.filter { [.queued, .running, .paused].contains($0.status) } }
    var history: [AgentRun] { runs.filter { [.done, .failed, .interrupted].contains($0.status) } }

    @discardableResult
    func enqueue(prompt: String, origin: AgentRunOrigin = .chat,
                 posture: SavedExecutionPosture? = nil) -> AgentRun {
        let run = AgentRun(origin: origin, prompt: prompt, posture: posture)
        document.runs.append(run)
        save()
        pump()
        return run
    }

    func pause(_ id: UUID) {
        guard let i = index(id), document.runs[i].status == .queued else { return }
        document.runs[i].status = .paused
        save()
    }

    func resume(_ id: UUID) {
        guard let i = index(id), document.runs[i].status == .paused else { return }
        document.runs[i].status = .queued
        save()
        pump()
    }

    /// Stops a queued/paused run (removes it from consideration) or an active
    /// run (cooperative cancel — the in-flight `Task` is cancelled, and the run
    /// is reclassified immediately so its slot frees without waiting for the
    /// runner to notice the cancellation).
    func stop(_ id: UUID) {
        guard let i = index(id) else { return }
        guard [.running, .queued, .paused].contains(document.runs[i].status) else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        document.runs[i].status = .interrupted
        document.runs[i].finishedAt = Date()
        save()
        pump()
    }

    /// Starts `.queued` runs (oldest first) until `runningCount == maxConcurrent`.
    /// Event-driven: called after every state change that could free or fill a
    /// slot (enqueue, resume, a run finishing, stop). Never spins/polls.
    func pump() {
        var runningCount = document.runs.filter { $0.status == .running }.count
        while runningCount < maxConcurrent,
              let id = document.runs.first(where: { $0.status == .queued })?.id {
            start(id)
            runningCount += 1
        }
    }

    private func start(_ id: UUID) {
        guard let i = index(id) else { return }
        document.runs[i].status = .running
        document.runs[i].startedAt = Date()
        save()
        let prompt = document.runs[i].prompt
        let posture = document.runs[i].posture
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.runner.execute(prompt: prompt, posture: posture) { line in
                Task { @MainActor in self.appendLog(id, line) }
            }
            guard !Task.isCancelled else { return }
            self.finish(id, outcome: outcome)
        }
    }

    private func finish(_ id: UUID, outcome: AgentRunOutcome) {
        // A stopped run may already have been reclassified to `.interrupted`
        // and had its task cleared before this continuation resumed — don't
        // resurrect it.
        guard tasks[id] != nil, let i = index(id) else { return }
        switch outcome {
        case .success(let text):
            document.runs[i].status = .done
            document.runs[i].result = text
        case .failure(let message):
            document.runs[i].status = .failed
            document.runs[i].result = message
        }
        document.runs[i].finishedAt = Date()
        tasks[id] = nil
        save()
        signalCenter?.emit(.runCompleted(document.runs[i]), from: .host)
        pump()
    }

    private func appendLog(_ id: UUID, _ line: String) {
        guard let i = index(id) else { return }
        document.runs[i].logs.append(line)
        save()
    }

    /// Attached after construction: the center is built in `finalizeBootstrap`,
    /// which runs after this manager exists. Held weakly, as at init.
    func attachSignalCenter(_ center: SignalCenter) { signalCenter = center }

    private func index(_ id: UUID) -> Int? { document.runs.firstIndex { $0.id == id } }
    private func save() { persistence.save(document) }
}
