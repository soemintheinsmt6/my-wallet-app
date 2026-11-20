import Foundation

/// A day the user drank alcohol. Days without one are alcohol-free.
public struct DrinkingDay: Identifiable, Codable, Sendable, Equatable {
    public var day: DayKey
    /// Optional, because a rough "I drank" is still worth recording.
    public var drinks: Int?
    public var note: String
    public var updatedAt: Date

    public var id: DayKey { day }

    public init(day: DayKey, drinks: Int? = nil, note: String = "", updatedAt: Date = Date()) {
        self.day = day
        self.drinks = drinks
        self.note = note
        self.updatedAt = updatedAt
    }
}

public enum DrinkingDayError: LocalizedError, Equatable {
    case invalidDrinks
    case noteTooLong
    case futureDay
    case saveInProgress

    public var errorDescription: String? {
        switch self {
        case .invalidDrinks: "Enter between 1 and \(DrinkingDay.maximumDrinks) drinks, or leave it blank."
        case .noteTooLong: "Keep the note under \(DrinkingDay.maximumNoteLength) characters."
        case .futureDay: "You can only mark today or an earlier day."
        case .saveInProgress: "Another change is being saved. Please try again."
        }
    }
}

extension DrinkingDay {
    public static let maximumDrinks = 99
    public static let maximumNoteLength = 500
}
