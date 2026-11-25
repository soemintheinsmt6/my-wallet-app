import Foundation

/// A year of drinking days laid out like a contribution chart, shaded by drinks.
public struct DrinkingHeatmap: Equatable, Sendable {
    public typealias Period = DayHeatmapPeriod
    public typealias MonthLabel = DayGrid.MonthLabel

    public struct Cell: DayHeatmapCell {
        public let day: DayKey
        /// 0 for an alcohol-free day, then 1 to 4 as drinks rise.
        public let level: Int
        public let drinks: Int?
        public var id: String { day.rawValue }
    }

    /// `weeks[column][row]`; `nil` pads the first and last weeks outside the period.
    public let weeks: [[Cell?]]
    public let monthLabels: [MonthLabel]
    public let period: Period
    public let today: DayKey
    public let first: DayKey
    public let last: DayKey
    public let drinkingDays: Int
    public let alcoholFreeDays: Int
    public let totalDrinks: Int
    public let longestAlcoholFreeStreak: Int
    /// The period's most visited places, up to five.
    public let mostVisitedPlaces: [DrinkingPlaceVisit]

    public init(days: [DrinkingDay], period: Period, today: DayKey, calendar: Calendar = .current) {
        let grid = DayGrid(period: period, today: today, calendar: calendar)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        weeks = grid.cells { Cell(day: $0, level: Self.level(for: byDay[$0]), drinks: byDay[$0]?.drinks) }
        monthLabels = grid.monthLabels
        self.period = period
        self.today = today
        first = grid.first
        last = grid.last
        let marked = grid.days.compactMap { byDay[$0] }
        drinkingDays = marked.count
        alcoholFreeDays = grid.days.count - marked.count
        totalDrinks = marked.reduce(0) { $0 + ($1.drinks ?? 0) }
        longestAlcoholFreeStreak = grid.longestRun { byDay[$0] == nil }
        mostVisitedPlaces = DrinkingPlaceVisit.mostVisited(in: marked)
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
