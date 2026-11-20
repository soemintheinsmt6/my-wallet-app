import Foundation
import SwiftData
import WalletDomain

/// One marked workout day. CloudKit cannot enforce uniqueness, so two devices marking the same day
/// offline can both upload a row; reads keep the newest per `dayValue` and saves fold the extras away.
/// Every property is defaulted, keeping this an additive, CloudKit-compatible model.
@Model
final class WorkoutDayRecord {
    var dayValue: String = ""
    var minutes: Int?
    /// A `WorkoutActivity` raw value, `nil` when none was chosen.
    var activityValue: String?
    /// Exercise names, one per line; names are normalized to a single line before saving.
    var exercisesValue: String = ""
    var note: String = ""
    var updatedAt: Date = Date()

    init(day: WorkoutDay) {
        dayValue = day.day.rawValue
        apply(day)
    }

    func apply(_ day: WorkoutDay) {
        minutes = day.minutes
        activityValue = day.activity?.rawValue
        exercisesValue = day.exercises.joined(separator: "\n")
        note = day.note
        updatedAt = day.updatedAt
    }

    var workoutDay: WorkoutDay? {
        guard let key = DayKey(rawValue: dayValue) else { return nil }
        return WorkoutDay(day: key, minutes: minutes, activity: activityValue.map(WorkoutActivity.init(storedValue:)),
                          exercises: exercisesValue.split(separator: "\n").map(String.init),
                          note: note, updatedAt: updatedAt)
    }
}

/// An exercise the user added to the preset list. Like workout days, two devices can upload the
/// same name; reads keep one per name ignoring case. Every property is defaulted for CloudKit.
@Model
final class WorkoutExerciseRecord {
    var name: String = ""
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }
}
