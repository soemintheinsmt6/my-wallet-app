import Foundation

/// A year of workout days laid out like a contribution chart, shaded by time spent.
public struct WorkoutHeatmap: Equatable, Sendable {
    public typealias Period = DayHeatmapPeriod
    public typealias MonthLabel = DayGrid.MonthLabel

    public struct Cell: DayHeatmapCell {
        public let day: DayKey
        /// 0 for a rest day, then 1 to 4 as minutes rise.
        public let level: Int
        public let minutes: Int?
        public let activity: WorkoutActivity?
        public var id: String { day.rawValue }
    }

    /// `weeks[column][row]`; `nil` pads the first and last weeks outside the period.
    public let weeks: [[Cell?]]
    public let monthLabels: [MonthLabel]
    public let period: Period
    public let today: DayKey
    public let first: DayKey
    public let last: DayKey
    public let workoutDays: Int
    public let restDays: Int
    public let totalMinutes: Int
    public let longestStreak: Int

    public init(days: [WorkoutDay], period: Period, today: DayKey, calendar: Calendar = .current) {
        let grid = DayGrid(period: period, today: today, calendar: calendar)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        weeks = grid.cells { day in
            let entry = byDay[day]
            return Cell(day: day, level: Self.level(for: entry), minutes: entry?.minutes, activity: entry?.activity)
        }
        monthLabels = grid.monthLabels
        self.period = period
        self.today = today
        first = grid.first
        last = grid.last
        let marked = grid.days.compactMap { byDay[$0] }
        workoutDays = marked.count
        restDays = grid.days.count - marked.count
        totalMinutes = marked.reduce(0) { $0 + ($1.minutes ?? 0) }
        longestStreak = grid.longestRun { byDay[$0] != nil }
    }

    /// A day marked without a duration shows at the lightest shade, since some exercise is known.
    public static func level(for day: WorkoutDay?) -> Int {
        guard let day else { return 0 }
        switch day.minutes ?? 1 {
        case ...20: return 1
        case 21...40: return 2
        case 41...60: return 3
        default: return 4
        }
    }
}
