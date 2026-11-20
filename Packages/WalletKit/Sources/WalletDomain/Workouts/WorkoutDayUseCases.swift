import Foundation

@MainActor
public struct WorkoutDayUseCases {
    private let repository: any WorkoutDayRepository

    public init(repository: any WorkoutDayRepository) { self.repository = repository }

    public func load() async throws -> [WorkoutDay] { try await repository.fetchWorkoutDays() }

    public func mark(_ day: DayKey, minutes: Int?, activity: WorkoutActivity?, note: String,
                     today: DayKey = DayKey(Date())) async throws {
        guard day <= today else { throw WorkoutDayError.futureDay }
        if let minutes {
            guard (1...WorkoutDay.maximumMinutes).contains(minutes) else { throw WorkoutDayError.invalidMinutes }
        }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= WorkoutDay.maximumNoteLength else { throw WorkoutDayError.noteTooLong }
        try Task.checkCancellation()
        try await repository.saveWorkoutDay(WorkoutDay(day: day, minutes: minutes, activity: activity, note: note))
    }

    public func unmark(_ day: DayKey) async throws {
        try Task.checkCancellation()
        try await repository.deleteWorkoutDay(day)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }
}
