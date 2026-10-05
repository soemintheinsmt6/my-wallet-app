import Foundation

/// A calendar day with no time or time zone, so a day marked in Yangon stays the same day when it
/// syncs to a device set to London.
public struct DayKey: Hashable, Comparable, Codable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Stored form, e.g. `2026-10-05`; sorts in date order as a plain string.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var rawValue: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public var id: String { rawValue }

    /// Start of this day in `calendar`.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? date(in: calendar), calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

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
