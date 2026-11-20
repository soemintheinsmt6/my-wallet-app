import Foundation

@MainActor
public struct WorkoutDayUseCases {
    private let repository: any WorkoutDayRepository

    public init(repository: any WorkoutDayRepository) { self.repository = repository }

    public func load() async throws -> [WorkoutDay] { try await repository.fetchWorkoutDays() }

    /// Saves the day as it will be stored and returns it: the note trimmed, and the exercises
    /// ordered and dropped altogether for an activity that does not list them.
    @discardableResult
    public func mark(_ day: DayKey, minutes: Int?, activity: WorkoutActivity?, exercises: [String] = [],
                     note: String, today: DayKey = DayKey(Date())) async throws -> WorkoutDay {
        guard day <= today else { throw WorkoutDayError.futureDay }
        if let minutes {
            guard (1...WorkoutDay.maximumMinutes).contains(minutes) else { throw WorkoutDayError.invalidMinutes }
        }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= WorkoutDay.maximumNoteLength else { throw WorkoutDayError.noteTooLong }
        let exercises = (activity?.tracksExercises ?? true) ? WorkoutExercises.ordered(exercises) : []
        guard exercises.count <= WorkoutExercises.maximumPerDay else { throw WorkoutDayError.tooManyExercises }
        guard exercises.allSatisfy({ $0.count <= WorkoutExercises.maximumNameLength }) else {
            throw WorkoutDayError.invalidExerciseName
        }
        try Task.checkCancellation()
        let saved = WorkoutDay(day: day, minutes: minutes, activity: activity, exercises: exercises, note: note)
        try await repository.saveWorkoutDay(saved)
        return saved
    }

    public func unmark(_ day: DayKey) async throws {
        try Task.checkCancellation()
        try await repository.deleteWorkoutDay(day)
    }

    public func loadExercises() async throws -> [String] { try await repository.fetchWorkoutExercises() }

    /// Adds an exercise of the user's own and returns the name to tick. A name already in the
    /// presets or the user's list, ignoring case, adds nothing and returns that spelling.
    @discardableResult
    public func addExercise(_ name: String) async throws -> String {
        let name = WorkoutExercises.normalizedName(name)
        guard !name.isEmpty, name.count <= WorkoutExercises.maximumNameLength else {
            throw WorkoutDayError.invalidExerciseName
        }
        if let preset = WorkoutExercises.presetName(matching: name) { return preset }
        if let existing = try await repository.fetchWorkoutExercises()
            .first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        try Task.checkCancellation()
        try await repository.saveWorkoutExercise(name)
        return name
    }

    /// Removes it from the list only; days that already name it keep it.
    public func deleteExercise(_ name: String) async throws {
        try Task.checkCancellation()
        try await repository.deleteWorkoutExercise(name)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }
}
