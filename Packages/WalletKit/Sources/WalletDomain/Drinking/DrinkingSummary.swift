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
        let inMonth = days.filter { $0.day.isInMonth(of: month) && $0.day <= today }
        drinkingDays = inMonth.count
        totalDrinks = inMonth.reduce(0) { $0 + ($1.drinks ?? 0) }
        alcoholFreeDays = max(0, DayKey.elapsedDays(in: month, today: today, calendar: calendar) - inMonth.count)
        daysSinceLastDrink = days.filter { $0.day <= today }.map(\.day).max().map {
            calendar.dateComponents([.day], from: $0.date(in: calendar), to: today.date(in: calendar)).day ?? 0
        }
    }
}
