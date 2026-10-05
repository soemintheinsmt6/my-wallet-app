import Foundation

/// A year of days laid out like a contribution chart: one column per week, one row per weekday,
/// starting from the calendar's first weekday.
public struct DrinkingHeatmap: Equatable, Sendable {
    public enum Period: Hashable, Sendable {
        /// The twelve months ending today.
        case pastYear
        case year(Int)
    }

    public struct Cell: Equatable, Sendable, Identifiable {
        public let day: DayKey
        /// 0 for an alcohol-free day, then 1 to 4 as drinks rise.
        public let level: Int
        public let drinks: Int?
        public var id: String { day.rawValue }
    }

    public struct MonthLabel: Equatable, Sendable {
        public let week: Int
        public let month: DayKey
    }

    /// `weeks[column][row]`; `nil` pads the first and last weeks outside the period.
    public let weeks: [[Cell?]]
    public let monthLabels: [MonthLabel]
    public let first: DayKey
    public let last: DayKey
    public let drinkingDays: Int
    public let alcoholFreeDays: Int
    public let totalDrinks: Int
    public let longestAlcoholFreeStreak: Int

    public init(days: [DrinkingDay], period: Period, today: DayKey, calendar: Calendar = .current) {
        switch period {
        case .pastYear:
            first = DayKey(calendar.date(byAdding: .year, value: -1, to: today.date(in: calendar)) ?? today.date(in: calendar),
                           calendar: calendar).adding(days: 1, calendar: calendar)
            last = today
        case .year(let year):
            first = DayKey(year: year, month: 1, day: 1)
            last = min(DayKey(year: year, month: 12, day: 31), today)
        }

        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let firstDate = first.date(in: calendar)
        let count = first > last ? 0
            : (calendar.dateComponents([.day], from: firstDate, to: last.date(in: calendar)).day ?? 0) + 1
        let lead = (calendar.component(.weekday, from: firstDate) - calendar.firstWeekday + 7) % 7

        var weeks = Array(repeating: [Cell?](repeating: nil, count: 7), count: (lead + count + 6) / 7)
        var labels: [MonthLabel] = []
        var drinking = 0, drinks = 0, streak = 0, longest = 0
        for offset in 0..<count {
            let key = DayKey(calendar.date(byAdding: .day, value: offset, to: firstDate) ?? firstDate, calendar: calendar)
            let entry = byDay[key]
            let index = lead + offset
            weeks[index / 7][index % 7] = Cell(day: key, level: Self.level(for: entry), drinks: entry?.drinks)
            if offset == 0 || key.day == 1 {
                labels.append(MonthLabel(week: index / 7, month: DayKey(year: key.year, month: key.month, day: 1)))
            }
            if let entry {
                drinking += 1
                drinks += entry.drinks ?? 0
                streak = 0
            } else {
                streak += 1
                longest = max(longest, streak)
            }
        }
        // A partial first month only keeps its label if there is room before the next one.
        if labels.count > 1, labels[1].week - labels[0].week < 3 { labels.removeFirst() }

        self.weeks = weeks
        monthLabels = labels
        drinkingDays = drinking
        alcoholFreeDays = count - drinking
        totalDrinks = drinks
        longestAlcoholFreeStreak = longest
    }

    /// A day marked without a count shows at the lightest shade, since some drinking is known.
    public static func level(for day: DrinkingDay?) -> Int {
        guard let day else { return 0 }
        switch day.drinks ?? 1 {
        case ...2: return 1
        case 3...4: return 2
        case 5...6: return 3
        default: return 4
        }
    }
}
