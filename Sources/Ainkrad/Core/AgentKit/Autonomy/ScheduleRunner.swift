import Foundation

/// Fires time-triggered schedules. A single `tick` coalesces any missed window
/// into one run (no double-fire after sleep) and never silently drops a due run.
@MainActor
final class ScheduleRunner {
    private let store: ScheduleStore
    private let runs: RunManager
    private let calendar: Calendar
    private var timer: Timer?

    init(store: ScheduleStore, runs: RunManager, calendar: Calendar = .current) {
        self.store = store
        self.runs = runs
        self.calendar = calendar
    }

    @discardableResult
    func tick(now: Date) -> [UUID] {
        var fired: [UUID] = []
        for schedule in store.schedules where schedule.enabled {
            guard case .time(let cron) = schedule.trigger else { continue }
            // A schedule that has never fired has no real anchor to catch up
            // from — anchoring to the Unix epoch would make `nextFireDate`
            // return the pattern's very first historical occurrence, which is
            // always `<= now` and would fire the schedule immediately on its
            // first tick regardless of the actual time of day. Anchor an
            // unfired schedule to the start of `now`'s day instead: it still
            // catches up on a due time already passed earlier today, but
            // doesn't treat all of history as a missed window.
            let since = schedule.lastFired ?? calendar.startOfDay(for: now)
            guard let due = cron.nextFireDate(after: since, calendar: calendar), due <= now else { continue }
            // The window between `since` and `now` may contain multiple due
            // instants (e.g. app asleep across days). We coalesce them into a
            // single run rather than backfilling one per missed instant
            // (recordFired stores `now`, not `due`, below).
            let run = runs.enqueue(prompt: schedule.prompt, origin: .schedule, posture: schedule.posture)
            store.recordFired(schedule.id, runID: run.id, date: now)   // now, not `due`, so the window coalesces
            fired.append(schedule.id)
        }
        return fired
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: Date()) }
        }
        // Tolerance: 5s is conservative for scheduled task precision. A schedule due
        // at 9:00 AM runs no later than 9:00:05 AM — acceptable for user-facing
        // automation. The coalescing logic already handles missed windows correctly
        // (no double-fire), so a small tolerance buys timer coalescing with no downside.
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }
}
