import Foundation
import Testing
import WalletDomain

struct StatisticsTests {
    private let start = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func record(_ account: Account, _ category: WalletCategory?, amount: Decimal, day: Int = 0,
                        kind: RecordKind = .expense, tag: UUID? = nil, destination: Account? = nil) -> WalletRecord {
        var draft = RecordDraft()
        draft.accountID = account.id
        draft.categoryID = category?.id
        draft.amount = amount
        draft.date = start.addingTimeInterval(Double(day) * 86400)
        draft.kind = kind
        draft.destinationAccountID = destination?.id
        draft.receivedAmount = destination == nil ? nil : amount
        draft.tagIDs = Set([tag].compactMap { $0 })
        return WalletRecord(id: UUID(), draft: draft, currencyCode: account.currencyCode)
    }

    @Test func totalsExcludeTransfersForeignCurrenciesExcludedAccountsAndEndBoundary() {
        let account = Account(name: "Cash", type: .cash)
        var settings = AccountSettings()
        settings.excludeFromStats = true
        let excluded = Account(name: "Excluded", type: .cash, settings: settings)
        let euro = Account(name: "Euro", type: .cash, currencyCode: "EUR")
        let category = WalletCategory(name: "Food")
        let records = [record(account, category, amount: 12), record(account, category, amount: 30, kind: .income),
                       record(account, category, amount: 99, kind: .transfer, destination: excluded),
                       record(excluded, category, amount: 100), record(euro, category, amount: 200),
                       record(account, category, amount: 500, day: 2)]
        let filter = StatisticsFilter(interval: DateInterval(start: start, duration: 2 * 86400), currencyCode: "USD")
        let result = WalletStatistics.calculate(records: records, accounts: [account, excluded, euro], categories: [category], filter: filter, calendar: calendar)
        #expect(result.income == 30)
        #expect(result.expenses == 12)
        #expect(result.net == 18)
        #expect(result.spendingTrend.map(\.amount) == [12, 0])
        #expect(result.expensesByCategory.first?.categoryID == category.id)
    }

    @Test func combinedAccountRootCategoryAndTagFiltersIncludeChildren() {
        let account = Account(name: "Cash", type: .cash)
        let other = Account(name: "Bank", type: .checking)
        let root = WalletCategory(name: "Food")
        let child = WalletCategory(parentID: root.id, name: "Lunch")
        let tag = UUID()
        let records = [record(account, child, amount: 10, tag: tag), record(account, root, amount: 5, tag: tag),
                       record(account, child, amount: 30), record(other, child, amount: 50, tag: tag),
                       record(account, nil, amount: 100, tag: tag)]
        let filter = StatisticsFilter(interval: DateInterval(start: start, duration: 86400), currencyCode: "USD",
                                      accountID: account.id, categoryID: root.id, tagID: tag)
        let result = WalletStatistics.calculate(records: records, accounts: [account, other], categories: [root, child], filter: filter, calendar: calendar)
        #expect(result.expenses == 15)
        #expect(result.expensesByCategory.map(\.amount) == [10, 5])
    }

    @Test func historyReversesFutureRecordsAndIncludesTransfersWhileActivityFiltersDoNotChangeBalances() {
        let account = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 70))
        let other = Account(name: "Bank", type: .checking)
        let records = [record(account, nil, amount: 10),
                       record(account, nil, amount: 15, day: 1, kind: .transfer, destination: other),
                       record(account, nil, amount: 5, day: 3)]
        let filter = StatisticsFilter(interval: DateInterval(start: start, duration: 2 * 86400), currencyCode: "USD", accountID: account.id, tagID: UUID())
        let result = WalletStatistics.calculate(records: records, accounts: [account, other], categories: [], filter: filter, calendar: calendar)
        #expect(result.expenses == 0)
        #expect(result.balanceHistory.map(\.amount) == [100, 90, 75])
    }

    @Test func missingCategoriesAreGroupedAsUncategorizedAndEmptyPeriodsHaveZeroTotals() {
        let account = Account(name: "Cash", type: .cash)
        let missing = WalletCategory(name: "Deleted")
        let filter = StatisticsFilter(interval: DateInterval(start: start, duration: 86400), currencyCode: "USD")
        let result = WalletStatistics.calculate(records: [record(account, missing, amount: 7)], accounts: [account], categories: [], filter: filter, calendar: calendar)
        #expect(result.expensesByCategory.first?.categoryID == nil)
        #expect(result.expenses == 7)
        let empty = WalletStatistics.calculate(records: [], accounts: [], categories: [], filter: filter, calendar: calendar)
        #expect(empty.net == 0)
        #expect(empty.spendingTrend.map(\.amount) == [0])
    }
}
