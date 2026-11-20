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

    /// Whether this day falls in the same calendar month as `month`.
    public func isInMonth(of month: DayKey) -> Bool {
        year == month.year && self.month == month.month
    }

    /// Days of `month` that have already started: all of a past month, none of a future one.
    static func elapsedDays(in month: DayKey, today: DayKey, calendar: Calendar) -> Int {
        if (month.year, month.month) > (today.year, today.month) { return 0 }
        if (month.year, month.month) == (today.year, today.month) { return today.day }
        let first = DayKey(year: month.year, month: month.month, day: 1).date(in: calendar)
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 0
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
