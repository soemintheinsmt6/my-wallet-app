import Foundation

/// The span a year chart covers.
public enum DayHeatmapPeriod: Hashable, Sendable {
    /// The twelve months ending today.
    case pastYear
    case year(Int)
}

/// A square in a year chart: 0 for an unmarked day, then 1 to 4 as the day's amount rises.
public protocol DayHeatmapCell: Identifiable, Equatable, Sendable {
    var day: DayKey { get }
    var level: Int { get }
}

/// A year of days laid out like a contribution chart: one column per week, one row per weekday,
/// starting from the calendar's first weekday. The drinking and workout charts fill it with their
/// own cells and counts.
public struct DayGrid: Equatable, Sendable {
    public struct MonthLabel: Equatable, Sendable {
        public let week: Int
        public let month: DayKey
    }

    public let period: DayHeatmapPeriod
    public let today: DayKey
    public let first: DayKey
    public let last: DayKey
    /// `weeks[column][row]`; `nil` pads the first and last weeks outside the period.
    public let weeks: [[DayKey?]]
    public let monthLabels: [MonthLabel]
    /// Every day of the period, oldest first.
    public let days: [DayKey]

    public init(period: DayHeatmapPeriod, today: DayKey, calendar: Calendar = .current) {
        self.period = period
        self.today = today
        switch period {
        case .pastYear:
            first = DayKey(calendar.date(byAdding: .year, value: -1, to: today.date(in: calendar)) ?? today.date(in: calendar),
                           calendar: calendar).adding(days: 1, calendar: calendar)
            last = today
        case .year(let year):
            first = DayKey(year: year, month: 1, day: 1)
            last = min(DayKey(year: year, month: 12, day: 31), today)
        }

        let firstDate = first.date(in: calendar)
        let count = first > last ? 0
            : (calendar.dateComponents([.day], from: firstDate, to: last.date(in: calendar)).day ?? 0) + 1
        let lead = (calendar.component(.weekday, from: firstDate) - calendar.firstWeekday + 7) % 7

        var weeks = Array(repeating: [DayKey?](repeating: nil, count: 7), count: (lead + count + 6) / 7)
        var labels: [MonthLabel] = []
        var days: [DayKey] = []
        days.reserveCapacity(count)
        for offset in 0..<count {
            let key = DayKey(calendar.date(byAdding: .day, value: offset, to: firstDate) ?? firstDate, calendar: calendar)
            let index = lead + offset
            weeks[index / 7][index % 7] = key
            days.append(key)
            if offset == 0 || key.day == 1 {
                labels.append(MonthLabel(week: index / 7, month: DayKey(year: key.year, month: key.month, day: 1)))
            }
        }
        // A partial first month only keeps its label if there is room before the next one.
        if labels.count > 1, labels[1].week - labels[0].week < 3 { labels.removeFirst() }

        self.weeks = weeks
        monthLabels = labels
        self.days = days
    }

    /// The layout with each day replaced by its cell.
    public func cells<Cell>(_ makeCell: (DayKey) -> Cell) -> [[Cell?]] {
        weeks.map { column in column.map { $0.map(makeCell) } }
    }

    /// The most consecutive days of the period that match.
    public func longestRun(where matches: (DayKey) -> Bool) -> Int {
        var run = 0, longest = 0
        for day in days {
            if matches(day) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }
}
