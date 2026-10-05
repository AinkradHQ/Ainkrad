import AinkradHostRuntime
import Foundation
import Observation

@MainActor
@Observable
final class ScheduleStore {
    private var document: SchedulesDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(SchedulesDocument.self) ?? SchedulesDocument()
    }

    var schedules: [AgentSchedule] { document.schedules }

    func upsert(_ schedule: AgentSchedule) {
        if let i = document.schedules.firstIndex(where: { $0.id == schedule.id }) {
            document.schedules[i] = schedule
        } else {
            document.schedules.append(schedule)
        }
        persistence.save(document)
    }

    func delete(_ id: UUID) {
        document.schedules.removeAll { $0.id == id }
        persistence.save(document)
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = document.schedules.firstIndex(where: { $0.id == id }) else { return }
        document.schedules[i].enabled = on
        persistence.save(document)
    }

    func recordFired(_ id: UUID, runID: UUID, date: Date) {
        guard let i = document.schedules.firstIndex(where: { $0.id == id }) else { return }
        document.schedules[i].lastFired = date
        document.schedules[i].lastRunID = runID
        persistence.save(document)
    }
}
