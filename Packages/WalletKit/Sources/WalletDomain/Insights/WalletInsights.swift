import Foundation

/// Derived observations about spending: comparisons, outliers and streaks.
///
/// Pure and calendar-injectable so every boundary — week starts, month lengths, "today" — can be
/// tested directly. Nothing here schedules or persists anything.
public struct WalletInsights: Sendable, Equatable {
    /// Spending across a period against the one before it.
    public struct Comparison: Sendable, Equatable {
        public let currencyCode: String
        public let current: Decimal
        public let previous: Decimal

        public var difference: Decimal { current - previous }

        /// `nil` when there is no previous spending to compare against — a percentage of zero
        /// would be meaningless, and "up 100%" from nothing is misleading.
        public var change: Double? {
            guard previous > 0 else { return nil }
            return NSDecimalNumber(decimal: difference / previous).doubleValue
        }

        public var isHigher: Bool { current > previous }

        /// Spending in the previous period up to the same point: the same days of last week, or
        /// the same stretch of last month. A period in progress is compared against this rather than
        /// the whole previous period, which early in a week would almost always read as "less".
        /// `previous` stays the whole period, for notices that report a finished one.
        public let previousSoFar: Decimal

        /// The change against the same point of the previous period; `nil` without spending there.
        public var changeSoFar: Double? {
            guard previousSoFar > 0 else { return nil }
            return NSDecimalNumber(decimal: (current - previousSoFar) / previousSoFar).doubleValue
        }

        public var isHigherSoFar: Bool { current > previousSoFar }

        public init(currencyCode: String, current: Decimal, previous: Decimal, previousSoFar: Decimal? = nil) {
            self.currencyCode = currencyCode
            self.current = current
            self.previous = previous
            self.previousSoFar = previousSoFar ?? previous
        }
    }

    /// A category spending materially more than its own recent norm.
    public struct Anomaly: Sendable, Equatable, Identifiable {
        public let categoryID: UUID
        public let currencyCode: String
        public let current: Decimal
        public let average: Decimal

        public var id: UUID { categoryID }
        public var multiple: Double {
            guard average > 0 else { return 0 }
            return NSDecimalNumber(decimal: current / average).doubleValue
        }

        public init(categoryID: UUID, currencyCode: String, current: Decimal, average: Decimal) {
            self.categoryID = categoryID
            self.currencyCode = currencyCode
            self.current = current
            self.average = average
        }
    }

    public let week: Comparison?
    public let month: Comparison?
    public let anomalies: [Anomaly]
    /// Consecutive days, ending today or yesterday, on which at least one record was added.
    public let loggingStreak: Int
    /// Consecutive completed days on which no budget was over its limit.
    public let underBudgetStreak: Int

    public init(week: Comparison? = nil, month: Comparison? = nil, anomalies: [Anomaly] = [],
                loggingStreak: Int = 0, underBudgetStreak: Int = 0) {
        self.week = week
        self.month = month
        self.anomalies = anomalies
        self.loggingStreak = loggingStreak
        self.underBudgetStreak = underBudgetStreak
    }

    public var isEmpty: Bool {
        week == nil && month == nil && anomalies.isEmpty && loggingStreak == 0 && underBudgetStreak == 0
    }
}

public enum WalletInsightsCalculator {
    /// A category must exceed this multiple of its own average to be called unusual.
    public static let anomalyMultiple = Decimal(string: "1.5")!
    /// …and must be worth mentioning at all; a coffee twice over is not news.
    public static let anomalyMinimumAmount = Decimal(10)
    /// Months of history the average is taken over.
    public static let anomalyHistoryMonths = 3

    public static func calculate(records: [WalletRecord], accounts: [Account],
                                 budgets: [BudgetProgress] = [], now: Date = Date(),
                                 calendar: Calendar = .current) -> WalletInsights {
        guard let currency = leadingCurrency(accounts) else { return WalletInsights() }
        let included = Set(accounts.filter { !$0.settings.excludeFromStats && $0.currencyCode == currency }
            .map(\.id))
        let expenses = records.filter {
            $0.draft.kind == .expense && $0.draft.countsAsActivity && $0.draft.accountID.map(included.contains) == true
        }

        return WalletInsights(
            week: comparison(expenses, unit: .weekOfYear, currency: currency, now: now, calendar: calendar),
            month: comparison(expenses, unit: .month, currency: currency, now: now, calendar: calendar),
            anomalies: anomalies(expenses, currency: currency, now: now, calendar: calendar),
            loggingStreak: loggingStreak(records, now: now, calendar: calendar),
            underBudgetStreak: underBudgetStreak(budgets, now: now))
    }

    /// The currency with the most included accounts, matching every other summary in the app.
    private static func leadingCurrency(_ accounts: [Account]) -> String? {
        let included = accounts.filter { !$0.settings.excludeFromStats }
        guard !included.isEmpty else { return nil }
        let counts = Dictionary(grouping: included, by: \.currencyCode).mapValues(\.count)
        return counts.max { left, right in
            left.value == right.value ? left.key > right.key : left.value < right.value
        }?.key
    }

    private static func comparison(_ expenses: [WalletRecord], unit: Calendar.Component,
                                   currency: String, now: Date,
                                   calendar: Calendar) -> WalletInsights.Comparison? {
        guard let current = calendar.dateInterval(of: unit, for: now),
              let previousDate = calendar.date(byAdding: unit, value: -1, to: now),
              let previous = calendar.dateInterval(of: unit, for: previousDate) else { return nil }
        // The same stretch of the previous period, as Statistics compares a period in progress.
        let soFar = PeriodComparison(interval: current, component: unit, now: now, calendar: calendar)
        return WalletInsights.Comparison(currencyCode: currency,
                                         current: total(expenses, in: current),
                                         previous: total(expenses, in: previous),
                                         previousSoFar: total(expenses, in: soFar.previous))
    }

    private static func total(_ expenses: [WalletRecord], in interval: DateInterval) -> Decimal {
        expenses.reduce(Decimal.zero) { sum, record in
            let date = record.draft.date
            return date >= interval.start && date < interval.end ? sum + record.draft.amount : sum
        }
    }

    /// Categories spending more this month than their own recent average.
    ///
    /// Compared against each category's own history rather than against other categories, because
    /// rent and coffee are not comparable and never will be.
    private static func anomalies(_ expenses: [WalletRecord], currency: String, now: Date,
                                  calendar: Calendar) -> [WalletInsights.Anomaly] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now) else { return [] }
        var history: [DateInterval] = []
        for offset in 1...anomalyHistoryMonths {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now),
                  let interval = calendar.dateInterval(of: .month, for: date) else { continue }
            history.append(interval)
        }
        guard !history.isEmpty else { return [] }

        let byCategory = Dictionary(grouping: expenses.filter { $0.draft.categoryID != nil },
                                    by: { $0.draft.categoryID! })
        var found: [WalletInsights.Anomaly] = []
        for (categoryID, records) in byCategory {
            let current = total(records, in: thisMonth)
            guard current >= anomalyMinimumAmount else { continue }
            let historical = history.map { total(records, in: $0) }
            // Every month of history counts, including months with no spending at all.
            let average = historical.reduce(Decimal.zero, +) / Decimal(historical.count)
            guard average > 0, current > average * anomalyMultiple else { continue }
            found.append(WalletInsights.Anomaly(categoryID: categoryID, currencyCode: currency,
                                                current: current, average: average))
        }
        // Biggest overshoot first, ties broken by identifier so the order never flickers.
        return found.sorted {
            $0.multiple == $1.multiple
                ? $0.categoryID.uuidString < $1.categoryID.uuidString
                : $0.multiple > $1.multiple
        }
    }

    /// Consecutive days with at least one record, counting back from today.
    ///
    /// A streak that ended yesterday still counts — the day is not over, and punishing someone at
    /// midnight for not having logged yet would be wrong.
    public static func loggingStreak(_ records: [WalletRecord], now: Date,
                                     calendar: Calendar = .current) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.draft.date) })
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor = days.contains(today) ? today : yesterday
        guard days.contains(cursor) else { return 0 }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Days since the most recent budget period that went over, capped at the shortest period in
    /// play. Zero when any budget is currently over its limit.
    private static func underBudgetStreak(_ budgets: [BudgetProgress], now: Date) -> Int {
        guard !budgets.isEmpty else { return 0 }
        guard !budgets.contains(where: { $0.spent >= $0.limit && $0.limit > 0 }) else { return 0 }
        // Days elapsed in the current period of the budget that started most recently: the run is
        // only as long as the shortest window every budget has been observed within.
        return budgets.compactMap { progress -> Int? in
            let elapsed = now.timeIntervalSince(progress.interval.start)
            guard elapsed >= 0 else { return nil }
            return Int(elapsed / 86400)
        }.min() ?? 0
    }
}
