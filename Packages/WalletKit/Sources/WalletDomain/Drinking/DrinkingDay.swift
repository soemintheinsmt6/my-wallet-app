import Foundation

/// A day the user drank alcohol. Days without one are alcohol-free.
public struct DrinkingDay: Identifiable, Codable, Sendable, Equatable {
    public var day: DayKey
    /// Optional, because a rough "I drank" is still worth recording.
    public var drinks: Int?
    /// Where the drinking happened — restaurants, bars, clubs — in the order they were added,
    /// since a night out often moves from one to the next.
    public var places: [String]
    public var note: String
    public var updatedAt: Date

    public var id: DayKey { day }

    public init(day: DayKey, drinks: Int? = nil, places: [String] = [], note: String = "",
                updatedAt: Date = Date()) {
        self.day = day
        self.drinks = drinks
        self.places = places
        self.note = note
        self.updatedAt = updatedAt
    }

    /// Older saves and backups have no places; they decode as none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(DayKey.self, forKey: .day)
        drinks = try container.decodeIfPresent(Int.self, forKey: .drinks)
        places = try container.decodeIfPresent([String].self, forKey: .places) ?? []
        note = try container.decode(String.self, forKey: .note)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public enum DrinkingDayError: LocalizedError, Equatable {
    case invalidDrinks
    case noteTooLong
    case futureDay
    case saveInProgress
    case tooManyPlaces
    case placeNameTooLong

    public var errorDescription: String? {
        switch self {
        case .invalidDrinks: "Enter between 1 and \(DrinkingDay.maximumDrinks) drinks, or leave it blank."
        case .noteTooLong: "Keep the note under \(DrinkingDay.maximumNoteLength) characters."
        case .futureDay: "You can only mark today or an earlier day."
        case .saveInProgress: "Another change is being saved. Please try again."
        case .tooManyPlaces: "Add up to \(DrinkingDay.maximumPlaces) places for a day."
        case .placeNameTooLong: "Keep each place under \(DrinkingDay.maximumPlaceNameLength) characters."
        }
    }
}

extension DrinkingDay {
    public static let maximumDrinks = 99
    public static let maximumNoteLength = 500
    public static let maximumPlaces = 10
    public static let maximumPlaceNameLength = 60

    /// One line with single spaces, so a name stores safely one per line and "Blue  Bar" is "Blue Bar".
    public static func normalizedPlace(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Each place once, ignoring case and accents, keeping the first spelling and the order added.
    public static func normalizedPlaces(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map(normalizedPlace).filter { !$0.isEmpty && seen.insert(PayeeSuggestions.fold($0)).inserted }
    }
}
