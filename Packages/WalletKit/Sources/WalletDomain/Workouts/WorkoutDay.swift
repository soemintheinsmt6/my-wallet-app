import Foundation

/// What a workout day was spent on.
public enum WorkoutActivity: String, CaseIterable, Codable, Sendable, Identifiable {
    case run
    case walk
    case cycle
    case swim
    case gym
    case yoga
    case sport
    case other

    public var id: String { rawValue }

    /// Stored values a later version may add read as Other rather than being lost as no activity.
    public init(storedValue: String) {
        self = WorkoutActivity(rawValue: storedValue) ?? .other
    }
}

/// A day the user worked out. Days without one are rest days.
public struct WorkoutDay: Identifiable, Codable, Sendable, Equatable {
    public var day: DayKey
    /// Optional, like the activity, because a rough "I worked out" is still worth recording.
    public var minutes: Int?
    public var activity: WorkoutActivity?
    public var note: String
    public var updatedAt: Date

    public var id: DayKey { day }

    public init(day: DayKey, minutes: Int? = nil, activity: WorkoutActivity? = nil, note: String = "",
                updatedAt: Date = Date()) {
        self.day = day
        self.minutes = minutes
        self.activity = activity
        self.note = note
        self.updatedAt = updatedAt
    }
}

public enum WorkoutDayError: LocalizedError, Equatable {
    case invalidMinutes
    case noteTooLong
    case futureDay
    case saveInProgress

    public var errorDescription: String? {
        switch self {
        case .invalidMinutes: "Enter between 1 and \(WorkoutDay.maximumMinutes) minutes, or leave it blank."
        case .noteTooLong: "Keep the note under \(WorkoutDay.maximumNoteLength) characters."
        case .futureDay: "You can only mark today or an earlier day."
        case .saveInProgress: "Another change is being saved. Please try again."
        }
    }
}

extension WorkoutDay {
    /// Ten hours, enough for a long hike or race day.
    public static let maximumMinutes = 600
    public static let maximumNoteLength = 500
}
