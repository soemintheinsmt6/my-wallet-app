import Foundation

/// Body parts and exercises offered for a workout, under the body part they train. Each group leads
/// with the body part itself, so a day can be marked "Chest" without naming every exercise.
public struct WorkoutExerciseGroup: Identifiable, Sendable, Equatable {
    public let name: String
    public let exercises: [String]
    public var id: String { name }
}

public enum WorkoutExercises {
    public static let presets: [WorkoutExerciseGroup] = [
        WorkoutExerciseGroup(name: "Chest", exercises: ["Chest", "Push-up", "Bench press", "Chest fly", "Dips"]),
        WorkoutExerciseGroup(name: "Back", exercises: ["Back", "Pull-up", "Row", "Lat pulldown", "Deadlift"]),
        WorkoutExerciseGroup(name: "Shoulders", exercises: ["Shoulders", "Shoulder press", "Lateral raise", "Pike push-up"]),
        WorkoutExerciseGroup(name: "Arms", exercises: ["Arms", "Biceps curl", "Triceps extension", "Diamond push-up"]),
        WorkoutExerciseGroup(name: "Legs", exercises: ["Legs", "Squat", "Lunge", "Leg press", "Calf raise", "Glute bridge"]),
        WorkoutExerciseGroup(name: "Core", exercises: ["Core", "Crunch", "Sit-up", "Plank", "Leg raise", "Russian twist"]),
        WorkoutExerciseGroup(name: "Cardio", exercises: ["Cardio", "Jumping jacks", "Burpee", "Mountain climber", "Skipping rope"]),
    ]

    public static let maximumPerDay = 40
    public static let maximumNameLength = 40

    private static let presetOrder: [String: Int] = {
        var order: [String: Int] = [:]
        for (index, name) in presets.flatMap(\.exercises).enumerated() { order[name.lowercased()] = index }
        return order
    }()

    private static let presetSpelling: [String: String] = Dictionary(
        presets.flatMap(\.exercises).map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first }
    )

    /// Trimmed, with runs of spaces and line breaks collapsed to one space, so a name can be
    /// stored on a line of its own.
    public static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The preset's own spelling when `name` matches one, ignoring case.
    public static func presetName(matching name: String) -> String? {
        presetSpelling[normalizedName(name).lowercased()]
    }

    /// One copy of each name, ignoring case: presets in list order, then the rest alphabetically.
    /// A day therefore always reads in the same order however its exercises were ticked.
    public static func ordered(_ names: [String]) -> [String] {
        var seen = Set<String>()
        let unique = names.map { presetName(matching: $0) ?? normalizedName($0) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return unique.sorted { lhs, rhs in
            switch (presetOrder[lhs.lowercased()], presetOrder[rhs.lowercased()]) {
            case let (left?, right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }
}
