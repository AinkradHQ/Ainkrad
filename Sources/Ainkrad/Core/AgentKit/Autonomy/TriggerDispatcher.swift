import Foundation

struct TriggerEvent: Sendable, Equatable {
    let scheduleID: UUID
    let payload: String
}

struct RateLimiter: Sendable {
    let minInterval: TimeInterval
    private var last: [UUID: Date] = [:]

    init(minInterval: TimeInterval) { self.minInterval = minInterval }

    mutating func allow(_ id: UUID, now: Date) -> Bool {
        if let prev = last[id], now.timeIntervalSince(prev) < minInterval { return false }
        last[id] = now
        return true
    }
}

@MainActor
final class TriggerDispatcher {
    private let store: ScheduleStore
    private let runs: RunManager
    private var limiter: RateLimiter

    init(store: ScheduleStore, runs: RunManager, minInterval: TimeInterval = 2) {
        self.store = store
        self.runs = runs
        self.limiter = RateLimiter(minInterval: minInterval)
    }

    @discardableResult
    func fire(_ event: TriggerEvent, now: Date = Date()) -> UUID? {
        guard let schedule = store.schedules.first(where: { $0.id == event.scheduleID }),
            schedule.enabled
        else { return nil }
        guard limiter.allow(event.scheduleID, now: now) else { return nil }
        let prompt =
            event.payload.isEmpty
            ? schedule.prompt
            : "\(schedule.prompt)\n\n[trigger payload]\n\(event.payload)"
        let run = runs.enqueue(prompt: prompt, origin: .event, posture: schedule.posture)
        store.recordFired(schedule.id, runID: run.id, date: now)
        return run.id
    }
}

/// Coalesces a burst of raw OS callbacks into a single trailing invocation.
@MainActor
final class Debouncer {
    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?

    init(interval: TimeInterval) { self.interval = interval }

    func schedule(_ work: @escaping @MainActor () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem { work() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }
}
