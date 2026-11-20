import Foundation

@MainActor
public protocol WorkoutDayRepository: AnyObject {
    func fetchWorkoutDays() async throws -> [WorkoutDay]
    /// Replaces whatever is stored for the same day.
    func saveWorkoutDay(_ day: WorkoutDay) async throws
    func deleteWorkoutDay(_ day: DayKey) async throws
    /// Exercises the user added to the preset list, one per name ignoring case, alphabetically.
    func fetchWorkoutExercises() async throws -> [String]
    /// Does nothing when the name is already stored, ignoring case.
    func saveWorkoutExercise(_ name: String) async throws
    /// Removes every stored copy of the name, ignoring case.
    func deleteWorkoutExercise(_ name: String) async throws
    func changes() -> AsyncStream<Void>
}
