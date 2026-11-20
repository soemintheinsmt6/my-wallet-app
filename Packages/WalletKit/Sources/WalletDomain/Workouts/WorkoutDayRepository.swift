import Foundation

@MainActor
public protocol WorkoutDayRepository: AnyObject {
    func fetchWorkoutDays() async throws -> [WorkoutDay]
    /// Replaces whatever is stored for the same day.
    func saveWorkoutDay(_ day: WorkoutDay) async throws
    func deleteWorkoutDay(_ day: DayKey) async throws
    func changes() -> AsyncStream<Void>
}
