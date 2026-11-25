import Foundation

public enum StatisticsGranularity: String, CaseIterable, Sendable {
    case day, week, month

    public var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// The groupings that give a period more than a handful of bars. Grouping a month by month,
    /// or a week by week, draws one bar and says nothing.
    public static func options(for interval: DateInterval) -> [StatisticsGranularity] {
        switch days(in: interval) {
        case ...14: [.day]
        case ...92: [.day, .week]
        case ...731: [.week, .month]
        default: [.month]
        }
    }

    /// The grouping a period opens with: days for anything up to a quarter, months beyond.
    public static func preferred(for interval: DateInterval) -> StatisticsGranularity {
        days(in: interval) <= 92 ? .day : .month
    }

    /// How finely balance history is sampled, independent of the spending grouping: daily for
    /// short periods so movements land on the day they happened, coarser as periods get long.
    static func history(for interval: DateInterval) -> StatisticsGranularity {
        switch days(in: interval) {
        case ...92: .day
        case ...731: .week
        default: .month
        }
    }

    private static func days(in interval: DateInterval) -> Double { (interval.duration / 86400).rounded() }
}

public struct StatisticsFilter: Sendable {
    public var interval: DateInterval
    public var currencyCode: String
    public var accountID: UUID?
    public var categoryID: UUID?
    public var tagID: UUID?
    public var granularity: StatisticsGranularity

    public init(interval: DateInterval, currencyCode: String, accountID: UUID? = nil,
                categoryID: UUID? = nil, tagID: UUID? = nil, granularity: StatisticsGranularity = .day) {
        self.interval = interval
        self.currencyCode = currencyCode
        self.accountID = accountID
        self.categoryID = categoryID
        self.tagID = tagID
        self.granularity = granularity
    }
}

public struct CategoryTotal: Identifiable, Sendable {
    public let categoryID: UUID?
    public let amount: Decimal
    public var id: String { categoryID?.uuidString ?? "uncategorized" }

    public init(categoryID: UUID?, amount: Decimal) {
        self.categoryID = categoryID
        self.amount = amount
    }
}

/// Spending under one label; `tagID` is `nil` for spending with no label.
public struct LabelTotal: Identifiable, Sendable, Equatable {
    public let tagID: UUID?
    public let amount: Decimal
    public var id: String { tagID?.uuidString ?? "unlabeled" }

    public init(tagID: UUID?, amount: Decimal) {
        self.tagID = tagID
        self.amount = amount
    }
}

public struct StatisticsPoint: Identifiable, Sendable {
    public let date: Date
    public let amount: Decimal
    public var id: Date { date }

    public init(date: Date, amount: Decimal) {
        self.date = date
        self.amount = amount
    }
}

/// A period set against the one before it, cut to the same length so a period still in progress
/// is compared like for like: the first ten days of this month against the first ten of last.
public struct PeriodComparison: Sendable, Equatable {
    /// The period up to now, or the whole period once it has ended.
    public let current: DateInterval
    /// The same stretch of the previous period.
    public let previous: DateInterval

    /// - Parameter component: the calendar unit the period spans, so "previous" is last month
    ///   rather than the 30 days before; `nil` for a custom range, which steps back by its length.
    public init(interval: DateInterval, component: Calendar.Component?, now: Date = Date(),
                calendar: Calendar = .current) {
        let elapsedEnd = now > interval.start && now < interval.end ? now : interval.end
        let elapsed = elapsedEnd.timeIntervalSince(interval.start)
        let previousStart = component.flatMap { calendar.date(byAdding: $0, value: -1, to: interval.start) }
            ?? interval.start.addingTimeInterval(-interval.duration)
        current = DateInterval(start: interval.start, end: elapsedEnd)
        previous = DateInterval(start: previousStart,
                                end: min(previousStart.addingTimeInterval(elapsed), interval.start))
    }

    /// Whole days covered so far, at least one, for a per-day average.
    public var elapsedDays: Int { max(1, Int((current.duration / 86400).rounded(.up))) }

    /// The relative change from `previous` to `current`; `nil` when there is nothing to compare.
    public static func change(from previous: Decimal, to current: Decimal) -> Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }
}

public struct WalletStatistics: Sendable {
    public let income: Decimal
    public let expenses: Decimal
    public let incomeByCategory: [CategoryTotal]
    public let expensesByCategory: [CategoryTotal]
    public let spendingTrend: [StatisticsPoint]
    public let balanceHistory: [StatisticsPoint]
    public var net: Decimal { income - expenses }

    /// Currency totals are never combined without an exchange rate. Transfers affect only history.
    /// History starts from the stored base (opening) balance; later balance edits are dated
    /// adjustment records, so they apply from their own date rather than retrospectively.
    /// It is sampled on its own schedule (see `StatisticsGranularity.history(for:)`) and stops at
    /// the step containing `now`, so a period still in progress does not plot days yet to come.
    public static func calculate(records: [WalletRecord], accounts: [Account], categories: [WalletCategory],
                                 filter: StatisticsFilter, calendar: Calendar = .current,
                                 now: Date = Date()) -> WalletStatistics {
        let included = accounts.filter {
            !$0.settings.excludeFromStats && $0.currencyCode == filter.currencyCode &&
                (filter.accountID == nil || $0.id == filter.accountID)
        }
        let accountIDs = Set(included.map(\.id))
        let categoryIDs = Set(categories.map(\.id))
        let activity = activity(records: records, accountIDs: accountIDs, categories: categories, filter: filter)
        func breakdown(_ kind: RecordKind) -> [CategoryTotal] {
            var values: [String: Decimal] = [:]
            for record in activity where record.draft.kind == kind {
                let id = record.draft.categoryID.flatMap { categoryIDs.contains($0) ? $0 : nil }
                values[id?.uuidString ?? "uncategorized", default: 0] += record.draft.amount
            }
            return values.map { CategoryTotal(categoryID: UUID(uuidString: $0.key), amount: $0.value) }
                .sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
        }
        let incomeCategories = breakdown(.income)
        let expenseCategories = breakdown(.expense)
        func delta(_ record: WalletRecord) -> Decimal {
            var result: Decimal = 0
            let draft = record.draft
            if let id = draft.accountID, accountIDs.contains(id) {
                result += draft.kind == .income ? draft.amount : -draft.amount
            }
            if draft.kind == .transfer, let id = draft.destinationAccountID, accountIDs.contains(id) {
                result += draft.receivedAmount ?? draft.amount
            }
            return result
        }
        let ledger = records.sorted { $0.draft.date < $1.draft.date }
        var balance = included.reduce(Decimal.zero) { $0 + $1.settings.currentBalance }
            - ledger.reduce(Decimal.zero) { $0 + delta($1) }
        var cursor = 0
        func advanceBalance(to date: Date) {
            while cursor < ledger.count && ledger[cursor].draft.date < date {
                balance += delta(ledger[cursor])
                cursor += 1
            }
        }
        advanceBalance(to: filter.interval.start)
        func steps(_ component: Calendar.Component) -> [DateInterval] {
            Self.steps(across: filter.interval, by: component, calendar: calendar)
        }
        let trend = steps(filter.granularity.component).map { step in
            StatisticsPoint(date: step.start, amount: activity
                .filter { $0.draft.kind == .expense && $0.draft.date >= step.start && $0.draft.date < step.end }
                .reduce(Decimal.zero) { $0 + $1.draft.amount })
        }
        var history = [StatisticsPoint(date: filter.interval.start, amount: balance)]
        for step in steps(StatisticsGranularity.history(for: filter.interval).component) where step.start <= now {
            advanceBalance(to: step.end)
            history.append(StatisticsPoint(date: step.end, amount: balance))
        }
        return WalletStatistics(income: incomeCategories.reduce(0) { $0 + $1.amount },
                                expenses: expenseCategories.reduce(0) { $0 + $1.amount },
                                incomeByCategory: incomeCategories, expensesByCategory: expenseCategories,
                                spendingTrend: trend, balanceHistory: history)
    }

    /// Records in the filter's window, accounts, category (with its children) and label that count
    /// as income or spending.
    static func activity(records: [WalletRecord], accountIDs: Set<UUID>, categories: [WalletCategory],
                         filter: StatisticsFilter) -> [WalletRecord] {
        let selectedCategories = Set(categories.filter {
            $0.id == filter.categoryID || $0.parentID == filter.categoryID
        }.map(\.id))
        return records.filter {
            let draft = $0.draft
            return draft.countsAsActivity && draft.accountID.map { accountIDs.contains($0) } == true &&
                draft.date >= filter.interval.start && draft.date < filter.interval.end &&
                (filter.categoryID == nil || draft.categoryID.map { selectedCategories.contains($0) } == true) &&
                (filter.tagID == nil || draft.tagIDs.contains(filter.tagID!))
        }
    }

    /// Consecutive steps of `component` across `interval`, clipped to its ends.
    static func steps(across interval: DateInterval, by component: Calendar.Component,
                      calendar: Calendar) -> [DateInterval] {
        var result: [DateInterval] = []
        var date = interval.start
        while date < interval.end {
            guard let next = calendar.dateInterval(of: component, for: date)?.end, next > date else { break }
            let end = min(next, interval.end)
            result.append(DateInterval(start: date, end: end))
            date = end
        }
        return result
    }

    /// Expenses under the same filters as `calculate`, split by whether they were a must, a need or
    /// a want. A category set to None takes its parent's nature; spending still without one
    /// (uncategorized, or None all the way up) is left out.
    public static func spendingByNature(records: [WalletRecord], accounts: [Account], categories: [WalletCategory],
                                        filter: StatisticsFilter, calendar: Calendar = .current) -> NatureSpending {
        let accountIDs = Set(accounts.filter {
            !$0.settings.excludeFromStats && $0.currencyCode == filter.currencyCode &&
                (filter.accountID == nil || $0.id == filter.accountID)
        }.map(\.id))
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func nature(of id: UUID?) -> CategoryNature? {
            guard let category = id.flatMap({ byID[$0] }) else { return nil }
            if category.nature != .none { return category.nature }
            guard let parent = category.parentID.flatMap({ byID[$0] }), parent.nature != .none else { return nil }
            return parent.nature
        }
        let tagged: [(record: WalletRecord, nature: CategoryNature)] =
            activity(records: records, accountIDs: accountIDs, categories: categories, filter: filter)
                .compactMap { record in
                    guard record.draft.kind == .expense, let nature = nature(of: record.draft.categoryID) else { return nil }
                    return (record, nature)
                }

        var trend: [NatureSpendingPoint] = []
        let sorted = tagged.sorted { $0.record.draft.date < $1.record.draft.date }
        var cursor = 0
        for step in steps(across: filter.interval, by: filter.granularity.component, calendar: calendar) {
            var sums: [CategoryNature: Decimal] = [:]
            while cursor < sorted.count && sorted[cursor].record.draft.date < step.end {
                sums[sorted[cursor].nature, default: 0] += sorted[cursor].record.draft.amount
                cursor += 1
            }
            for nature in NatureSpending.natures {
                if let amount = sums[nature], amount != 0 {
                    trend.append(NatureSpendingPoint(date: step.start, nature: nature, amount: amount))
                }
            }
        }

        var categoryTotals: [CategoryNature: [UUID: Decimal]] = [:]
        for (record, nature) in tagged {
            categoryTotals[nature, default: [:]][record.draft.categoryID!, default: 0] += record.draft.amount
        }
        let byCategory = categoryTotals.mapValues { totals in
            totals.map { CategoryTotal(categoryID: $0.key, amount: $0.value) }
        }
        return NatureSpending(trend: trend, byCategory: byCategory)
    }
}

/// One nature's spending in one step of the period.
public struct NatureSpendingPoint: Identifiable, Sendable, Equatable {
    public let date: Date
    public let nature: CategoryNature
    public let amount: Decimal
    public var id: String { "\(date.timeIntervalSinceReferenceDate)-\(nature.rawValue)" }

    public init(date: Date, nature: CategoryNature, amount: Decimal) {
        self.date = date
        self.nature = nature
        self.amount = amount
    }
}

/// Spending split into musts, needs and wants: over time, and by category within each.
public struct NatureSpending: Sendable {
    /// The natures spending is split into, in the order they stack and are listed.
    public static let natures: [CategoryNature] = [.must, .need, .want]

    /// Non-zero amounts only, in date order then nature order.
    public let trend: [NatureSpendingPoint]
    private let byCategory: [CategoryNature: [CategoryTotal]]

    public init(trend: [NatureSpendingPoint], byCategory: [CategoryNature: [CategoryTotal]]) {
        self.trend = trend
        self.byCategory = byCategory
    }

    /// The trend for one nature, or every nature when `nature` is `nil`.
    public func trend(_ nature: CategoryNature?) -> [NatureSpendingPoint] {
        nature.map { nature in trend.filter { $0.nature == nature } } ?? trend
    }

    /// Spending per category for one nature, or across all of them, largest first.
    public func categories(_ nature: CategoryNature?) -> [CategoryTotal] {
        let values = nature.map { byCategory[$0] ?? [] } ?? byCategory.values.flatMap { $0 }
        return values.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }

    public func total(_ nature: CategoryNature?) -> Decimal {
        categories(nature).reduce(0) { $0 + $1.amount }
    }
}

extension WalletStatistics {

    /// Expenses grouped by label over the filter's window, largest first, with unlabeled spending
    /// as its own entry so the parts add up to the same total as the category breakdown.
    ///
    /// Records are one label each now, but older ones may carry several; such a record's amount
    /// is split evenly between them rather than counted once per label, which would overstate the
    /// total. Labels that no longer exist count as unlabeled.
    public static func expensesByLabel(records: [WalletRecord], accounts: [Account], tags: [WalletTag],
                                       filter: StatisticsFilter) -> [LabelTotal] {
        let accountIDs = Set(accounts.filter {
            !$0.settings.excludeFromStats && $0.currencyCode == filter.currencyCode &&
                (filter.accountID == nil || $0.id == filter.accountID)
        }.map(\.id))
        let known = Set(tags.map(\.id))
        var values: [UUID?: Decimal] = [:]
        for record in records {
            let draft = record.draft
            guard draft.kind == .expense, draft.countsAsActivity, let account = draft.accountID, accountIDs.contains(account),
                  draft.date >= filter.interval.start, draft.date < filter.interval.end else { continue }
            let labels = draft.tagIDs.filter { known.contains($0) }
            if labels.isEmpty {
                values[nil, default: 0] += draft.amount
            } else {
                let share = draft.amount / Decimal(labels.count)
                for label in labels { values[label, default: 0] += share }
            }
        }
        return values.map { LabelTotal(tagID: $0.key, amount: $0.value) }
            .sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }
}
