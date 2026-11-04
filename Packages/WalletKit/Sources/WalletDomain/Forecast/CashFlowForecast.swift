import Foundation

/// One planned movement of money through an account: a recurring record not yet generated, or an
/// unpaid bill.
public struct ForecastEvent: Identifiable, Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case recurring(seriesID: UUID, index: Int)
        case bill(billID: UUID, index: Int)
    }

    public let source: Source
    /// When it lands; one already due lands today, since it has not reached the balance yet.
    public let date: Date
    public let title: String
    /// What it does to this account's balance: negative for money out.
    public let amount: Decimal
    /// A bill whose due date has passed unpaid, or a recurring record waiting to be generated.
    public let isOverdue: Bool

    public var id: String {
        switch source {
        case .recurring(let series, let index): "recurring.\(series.uuidString).\(index).\(amount)"
        case .bill(let bill, let index): "bill.\(bill.uuidString).\(index)"
        }
    }

    public init(source: Source, date: Date, title: String, amount: Decimal, isOverdue: Bool = false) {
        self.source = source
        self.date = date
        self.title = title
        self.amount = amount
        self.isOverdue = isOverdue
    }
}

/// An account's balance from today to the end of the forecast, moved by what is planned for it.
public struct AccountForecast: Identifiable, Sendable, Equatable {
    /// A balance at a moment: the lowest one reached, or the first below the account's threshold.
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let balance: Decimal

        public init(date: Date, balance: Decimal) {
            self.date = date
            self.balance = balance
        }
    }

    public let account: Account
    public let start: Date
    public let end: Date
    /// Planned events in the order they land.
    public let events: [ForecastEvent]
    /// The balance a warning is given below, or `nil` for an account that is meant to run
    /// negative (a card or a loan) and has no minimum set.
    public let threshold: Decimal?

    public var id: UUID { account.id }
    public var startingBalance: Decimal { account.settings.currentBalance }
    public var endingBalance: Decimal { events.reduce(startingBalance) { $0 + $1.amount } }

    /// The balance after each event, in order.
    public var runningBalances: [Decimal] {
        var balance = startingBalance
        return events.map { balance += $0.amount; return balance }
    }

    /// The lowest balance the account reaches, when an event takes it below where it starts.
    public var lowest: Point? {
        var lowest: Point?
        for (event, balance) in zip(events, runningBalances) where balance < (lowest?.balance ?? startingBalance) {
            lowest = Point(date: event.date, balance: balance)
        }
        return lowest
    }

    /// When the balance first falls below the threshold, today if it already has.
    public var firstBelowThreshold: Point? {
        guard let threshold else { return nil }
        if startingBalance < threshold { return Point(date: start, balance: startingBalance) }
        for (event, balance) in zip(events, runningBalances) where balance < threshold {
            return Point(date: event.date, balance: balance)
        }
        return nil
    }

    /// The balance at the end of each day from today to the last day, for a chart.
    public func dailyBalances(calendar: Calendar = .current) -> [StatisticsPoint] {
        var points: [StatisticsPoint] = []
        var balance = startingBalance
        var remaining = events[...]
        var day = calendar.startOfDay(for: start)
        while day <= end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            while let event = remaining.first, event.date < next {
                balance += event.amount
                remaining = remaining.dropFirst()
            }
            points.append(StatisticsPoint(date: day, amount: balance))
            day = next
        }
        return points
    }

    public init(account: Account, start: Date, end: Date, events: [ForecastEvent], threshold: Decimal?) {
        self.account = account
        self.start = start
        self.end = end
        self.events = events
        self.threshold = threshold
    }
}

/// Projects account balances forward from the recurring records and bills already planned.
///
/// Nothing is guessed from past spending: the forecast only moves a balance by what the person has
/// scheduled, so every figure can be traced to a series or a bill they can open and change.
///
/// Recurring series contribute each occurrence the generator would write, honouring skipped and
/// modified occurrences; paused and cancelled series contribute nothing. Unpaid bills contribute
/// each due date as an expense on their account, as paying one with Add Expense records it. An
/// occurrence or bill already due has not reached the balance, so it lands today.
///
/// A bill is often a reminder for a payment a recurring series already records. When a bill falls
/// within `LedgerMatcher.postingLagDays` of a recurring expense of the same amount on the same
/// account, only the recurring one is counted, so the payment is not taken twice.
public enum CashFlowForecaster {
    public static let defaultDays = 30
    /// Bounds a daily series over a long horizon; far more than any horizon offered needs.
    static let maximumOccurrencesPerSeries = 1_000

    /// Forecasts for accounts with something planned, in the accounts' order.
    public static func forecast(accounts: [Account], series: [RecurringSeries], occurrences: [ScheduledOccurrence],
                                bills: [BillReminder], categories: [WalletCategory] = [], now: Date = Date(),
                                days: Int = defaultDays, calendar: Calendar = .current) -> [AccountForecast] {
        guard days > 0, let end = calendar.date(byAdding: .day, value: days, to: now) else { return [] }
        let known = Set(accounts.map(\.id))
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let receipts = Dictionary(grouping: occurrences, by: \.seriesID)

        var byAccount: [UUID: [ForecastEvent]] = [:]
        for item in series where item.state == .active {
            for (draft, index) in planned(item, receipts: receipts[item.id] ?? [], through: end) {
                for (accountID, amount) in draft.balanceEffects where known.contains(accountID) && amount != 0 {
                    byAccount[accountID, default: []].append(
                        ForecastEvent(source: .recurring(seriesID: item.id, index: index), date: max(draft.date, now),
                                      title: title(for: draft, names: names), amount: amount, isOverdue: draft.date < now))
                }
            }
        }
        for bill in bills where !bill.isPaid {
            guard let accountID = bill.accountID, known.contains(accountID) else { continue }
            for (due, index) in dueDates(of: bill, through: end) {
                let event = ForecastEvent(source: .bill(billID: bill.id, index: index), date: max(due, now),
                                          title: bill.name, amount: -bill.amount, isOverdue: due < now)
                guard !isRecorded(event, by: byAccount[accountID] ?? [], calendar: calendar) else { continue }
                byAccount[accountID, default: []].append(event)
            }
        }

        return accounts.compactMap { account in
            guard let events = byAccount[account.id], !events.isEmpty else { return nil }
            let ordered = events.sorted { ($0.date, $0.title, $0.id) < ($1.date, $1.title, $1.id) }
            return AccountForecast(account: account, start: now, end: end, events: ordered, threshold: threshold(for: account))
        }
    }

    /// The balance worth a warning: the account's own minimum when it alerts on one, else zero for
    /// money the person holds. Cards, loans and investments routinely sit below zero or swing, so
    /// they warn only on a minimum the person set.
    public static func threshold(for account: Account) -> Decimal? {
        if account.settings.notifyBelowMinimum { return account.settings.minimumBalance }
        switch account.type {
        case .cash, .checking, .savings, .other: return 0
        case .creditCard, .loansAndMortgage, .investments: return nil
        }
    }

    /// The drafts the generator would write for a series through `end`, with their occurrence index.
    static func planned(_ series: RecurringSeries, receipts: [ScheduledOccurrence], through end: Date)
        -> [(draft: RecordDraft, index: Int)] {
        let receiptsByIndex = Dictionary(receipts.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        var planned: [(RecordDraft, Int)] = []
        // A modified occurrence may move before or after its regular date, so it is placed by its
        // own date whatever its index, as the generator does.
        for receipt in receipts where !receipt.completed && !receipt.skipped {
            guard var draft = receipt.overrideDraft, draft.date <= end else { continue }
            draft.recurrence = nil
            planned.append((draft, receipt.index))
        }
        var index = series.nextIndex
        while index < series.nextIndex + maximumOccurrencesPerSeries,
              let date = series.rule.date(start: series.startDate, index: index), date <= end {
            defer { index += 1 }
            if let receipt = receiptsByIndex[index],
               receipt.skipped || receipt.completed || receipt.overrideDraft != nil { continue }
            var draft = series.template
            draft.date = date
            planned.append((draft, index))
        }
        return planned
    }

    /// Unpaid due dates of a bill through `end`, starting with the one currently due.
    static func dueDates(of bill: BillReminder, through end: Date) -> [(date: Date, index: Int)] {
        guard let recurrence = bill.recurrence else {
            return bill.nextIndex == 0 && bill.dueDate <= end ? [(bill.dueDate, 0)] : []
        }
        var dates: [(Date, Int)] = []
        var index = bill.nextIndex
        while index < bill.nextIndex + maximumOccurrencesPerSeries,
              let date = recurrence.date(start: bill.dueDate, index: index), date <= end {
            dates.append((date, index))
            index += 1
        }
        return dates
    }

    /// Whether a recurring expense already takes this bill's amount from the account near its date.
    private static func isRecorded(_ bill: ForecastEvent, by events: [ForecastEvent], calendar: Calendar) -> Bool {
        events.contains { event in
            guard case .recurring = event.source, event.amount == bill.amount else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.date),
                                               to: calendar.startOfDay(for: bill.date)).day ?? .max
            return abs(days) <= LedgerMatcher.postingLagDays
        }
    }

    private static func title(for draft: RecordDraft, names: [UUID: String]) -> String {
        let payee = draft.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        if !payee.isEmpty { return payee }
        if let name = draft.categoryID.flatMap({ names[$0] }) { return name }
        switch draft.kind {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }
}
