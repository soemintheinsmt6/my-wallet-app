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

public struct WalletStatistics: Sendable {
    public let income: Decimal
    public let expenses: Decimal
    public let incomeByCategory: [CategoryTotal]
    public let expensesByCategory: [CategoryTotal]
    public let spendingTrend: [StatisticsPoint]
    public let balanceHistory: [StatisticsPoint]
    public var net: Decimal { income - expenses }

    /// Currency totals are never combined without an exchange rate. Transfers affect only history.
    /// History uses the current stored base balance, so manual balance corrections are retrospective.
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
        let selectedCategories = Set(categories.filter {
            $0.id == filter.categoryID || $0.parentID == filter.categoryID
        }.map(\.id))
        let activity = records.filter {
            let draft = $0.draft
            return draft.kind != .transfer && draft.accountID.map { accountIDs.contains($0) } == true &&
                draft.date >= filter.interval.start && draft.date < filter.interval.end &&
                (filter.categoryID == nil || draft.categoryID.map { selectedCategories.contains($0) } == true) &&
                (filter.tagID == nil || draft.tagIDs.contains(filter.tagID!))
        }
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
        /// Consecutive steps of `component` across the filter's window, clipped to its ends.
        func steps(_ component: Calendar.Component) -> [DateInterval] {
            var result: [DateInterval] = []
            var date = filter.interval.start
            while date < filter.interval.end {
                guard let next = calendar.dateInterval(of: component, for: date)?.end, next > date else { break }
                let end = min(next, filter.interval.end)
                result.append(DateInterval(start: date, end: end))
                date = end
            }
            return result
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
            guard draft.kind == .expense, let account = draft.accountID, accountIDs.contains(account),
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
