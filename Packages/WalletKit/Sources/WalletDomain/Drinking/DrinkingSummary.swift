import Foundation

/// Figures for one calendar month, counting only days up to today.
public struct DrinkingSummary: Equatable, Sendable {
    public let drinkingDays: Int
    public let alcoholFreeDays: Int
    /// Sum of the days that recorded a count; days marked without one add nothing.
    public let totalDrinks: Int
    /// Whole days since the most recent drinking day, or `nil` when none is recorded yet.
    public let daysSinceLastDrink: Int?

    public init(days: [DrinkingDay], month: DayKey, today: DayKey, calendar: Calendar = .current) {
        let inMonth = days.filter { $0.day.year == month.year && $0.day.month == month.month && $0.day <= today }
        drinkingDays = inMonth.count
        totalDrinks = inMonth.reduce(0) { $0 + ($1.drinks ?? 0) }
        alcoholFreeDays = max(0, Self.elapsedDays(in: month, today: today, calendar: calendar) - inMonth.count)
        daysSinceLastDrink = days.filter { $0.day <= today }.map(\.day).max().map {
            calendar.dateComponents([.day], from: $0.date(in: calendar), to: today.date(in: calendar)).day ?? 0
        }
    }

    /// Days of `month` that have already started: all of a past month, none of a future one.
    static func elapsedDays(in month: DayKey, today: DayKey, calendar: Calendar) -> Int {
        if (month.year, month.month) > (today.year, today.month) { return 0 }
        if (month.year, month.month) == (today.year, today.month) { return today.day }
        let first = DayKey(year: month.year, month: month.month, day: 1).date(in: calendar)
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 0
    }
}
