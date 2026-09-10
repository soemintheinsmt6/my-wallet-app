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
                            budgets: [BudgetProgress], now: Date = Date(),
                            calendar: Calendar = .current) -> WalletSnapshot {
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

        return WalletSnapshot(generatedAt: now, balances: balances, month: month,
                              recent: Array(recent), budgets: Array(summaries))
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
            title = draft.kind == .transfer ? draft.kind.title : "Uncategorized"
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
