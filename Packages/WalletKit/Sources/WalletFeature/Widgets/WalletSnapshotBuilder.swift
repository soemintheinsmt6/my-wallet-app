import Foundation
import WalletDomain

/// Builds the widget snapshot from loaded wallet data.
///
/// Pure and synchronous so it can be unit tested without persistence. Symbols and colors are
/// resolved here, using the same presentation rules as the in-app rows, so the widget extension
/// needs no category or account lookup of its own.
public enum WalletSnapshotBuilder {
    public static let recentLimit = 6
    public static let budgetLimit = 4

    public static func make(records: [WalletRecord], accounts: [Account], categories: [WalletCategory],
                            budgets: [BudgetProgress], numberScale: NumberScale = .automatic,
                            now: Date = Date(), calendar: Calendar = .current) -> WalletSnapshot {
        let included = accounts.filter { !$0.settings.excludeFromStats }
        let balances = Dictionary(grouping: included, by: \.currencyCode)
            .map { code, group in
                WalletSnapshot.Balance(currencyCode: code,
                                       total: group.reduce(0) { $0 + $1.settings.currentBalance },
                                       accountCount: group.count)
            }
            .sorted { $0.currencyCode < $1.currencyCode }

        let month = month(records: records, accounts: accounts, categories: categories,
                          balances: balances, now: now, calendar: calendar)

        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let accountsByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = records
            .sorted { $0.draft.date > $1.draft.date }
            .prefix(recentLimit)
            .map { entry(for: $0, categories: categoriesByID, accounts: accountsByID) }

        let summaries = budgets
            .sorted { $0.ratio > $1.ratio }
            .prefix(budgetLimit)
            .map {
                WalletSnapshot.BudgetProgressSummary(id: $0.budget.id, name: $0.budget.name,
                                                     spent: $0.spent, limit: $0.limit,
                                                     currencyCode: $0.budget.currencyCode, status: $0.status)
            }

        let options = included.map {
            WalletSnapshot.Option(id: $0.id, title: $0.name, symbol: $0.symbol,
                                  currencyCode: $0.currencyCode)
        }
        let quick = quickCategories(records: records, categories: categories, categoriesByID: categoriesByID)

        return WalletSnapshot(generatedAt: now, balances: balances, month: month,
                              recent: Array(recent), budgets: Array(summaries),
                              accounts: options, quickCategories: quick,
                              todaySpend: todaySpend(records: records, accounts: accounts,
                                                     balances: balances, now: now, calendar: calendar),
                              numberScale: numberScale)
    }

    /// The expense categories used most often, so quick entry away from the phone offers the
    /// handful that actually matter rather than the whole tree.
    private static func quickCategories(records: [WalletRecord], categories: [WalletCategory],
                                        categoriesByID: [UUID: WalletCategory]) -> [WalletSnapshot.Option] {
        let expenses = records.filter { $0.draft.kind == .expense }
        let counts = Dictionary(grouping: expenses.compactMap { $0.draft.categoryID }, by: { $0 })
            .mapValues(\.count)
        let ranked = categories
            .filter { counts[$0.id] != nil }
            .sorted {
                counts[$0.id] == counts[$1.id]
                    ? $0.id.uuidString < $1.id.uuidString
                    : counts[$0.id, default: 0] > counts[$1.id, default: 0]
            }
            .prefix(quickCategoryLimit)
        return ranked.map {
            WalletSnapshot.Option(id: $0.id,
                                  title: RecordCSV.path(for: $0.id, in: categoriesByID),
                                  symbol: $0.symbol,
                                  colorValue: $0.colorToken.rawValue)
        }
    }

    public static let quickCategoryLimit = 8

    /// Expenses recorded today in the leading currency; transfers are excluded as everywhere else.
    private static func todaySpend(records: [WalletRecord], accounts: [Account],
                                   balances: [WalletSnapshot.Balance], now: Date,
                                   calendar: Calendar) -> Decimal {
        let snapshot = WalletSnapshot(balances: balances)
        guard let currency = snapshot.primaryBalance?.currencyCode,
              let day = calendar.dateInterval(of: .day, for: now) else { return 0 }
        let included = Set(accounts.filter { !$0.settings.excludeFromStats && $0.currencyCode == currency }
            .map(\.id))
        return records.reduce(Decimal.zero) { total, record in
            let draft = record.draft
            guard draft.kind == .expense, draft.countsAsActivity, let account = draft.accountID, included.contains(account),
                  draft.date >= day.start, draft.date < day.end else { return total }
            return total + draft.amount
        }
    }

    private static func month(records: [WalletRecord], accounts: [Account], categories: [WalletCategory],
                              balances: [WalletSnapshot.Balance], now: Date,
                              calendar: Calendar) -> WalletSnapshot.Month? {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return nil }
        // The month figures follow the same currency the balance widget leads with.
        let snapshot = WalletSnapshot(balances: balances)
        guard let currency = snapshot.primaryBalance?.currencyCode else { return nil }
        let statistics = WalletStatistics.calculate(records: records, accounts: accounts, categories: categories,
                                                    filter: StatisticsFilter(interval: interval, currencyCode: currency),
                                                    calendar: calendar)
        return WalletSnapshot.Month(currencyCode: currency, start: interval.start,
                                    income: statistics.income, expenses: statistics.expenses)
    }

    private static func entry(for record: WalletRecord, categories: [UUID: WalletCategory],
                              accounts: [UUID: Account]) -> WalletSnapshot.Entry {
        let draft = record.draft
        let category = draft.categoryID.flatMap { categories[$0] }
        let title: String
        if let category {
            if let parent = category.parentID.flatMap({ categories[$0] }) {
                title = "\(parent.name) / \(category.name)"
            } else {
                title = category.name
            }
        } else {
            title = draft.isAdjustment ? RecordDraft.adjustmentTitle
                : draft.kind == .transfer ? draft.kind.title : "Uncategorized"
        }

        let account = draft.accountID.flatMap { accounts[$0] }
        let subtitle: String
        if draft.kind == .transfer {
            let destination = draft.destinationAccountID.flatMap { accounts[$0] }
            subtitle = "\(account?.name ?? "Unlinked") → \(destination?.name ?? "Unlinked")"
        } else if !draft.payee.isEmpty {
            subtitle = draft.payee
        } else {
            subtitle = account?.name ?? "Unlinked account"
        }

        return WalletSnapshot.Entry(id: record.id, title: title, subtitle: subtitle,
                                    amount: draft.amount, currencyCode: record.currencyCode,
                                    kind: draft.kind, date: draft.date,
                                    symbol: category?.symbol ?? draft.kind.symbol,
                                    colorValue: category?.colorToken.rawValue)
    }
}
