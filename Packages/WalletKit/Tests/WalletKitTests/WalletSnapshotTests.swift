import Foundation
import Testing
import WalletDomain
@testable import WalletFeature

struct WalletSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_704_110_400) // 2024-01-01 12:00 UTC

    private func account(_ name: String, currency: String = "USD", balance: Decimal = 100,
                         excluded: Bool = false) -> Account {
        Account(name: name, type: .cash, currencyCode: currency,
                settings: AccountSettings(currentBalance: balance, excludeFromStats: excluded))
    }

    private func record(amount: Decimal = 10, kind: RecordKind = .expense, account: Account,
                        destination: Account? = nil, category: UUID? = nil, dayOffset: Int = 0,
                        payee: String = "") -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = account.id
        draft.destinationAccountID = destination?.id
        draft.amount = amount
        draft.categoryID = category
        draft.payee = payee
        draft.date = now.addingTimeInterval(Double(dayOffset) * 86400)
        return WalletRecord(id: UUID(), draft: draft, currencyCode: account.currencyCode)
    }

    // MARK: - Builder

    @Test func balancesGroupByCurrencyAndExcludeAccountsOmittedFromStats() {
        let accounts = [account("Cash", balance: 100), account("Savings", balance: 250),
                        account("Euro", currency: "EUR", balance: 40),
                        account("Hidden", balance: 999, excluded: true)]
        let snapshot = WalletSnapshotBuilder.make(records: [], accounts: accounts, categories: [],
                                                  budgets: [], now: now)

        #expect(snapshot.balances.count == 2)
        #expect(snapshot.balances.first { $0.currencyCode == "USD" }?.total == 350)
        #expect(snapshot.balances.first { $0.currencyCode == "USD" }?.accountCount == 2)
        #expect(snapshot.balances.first { $0.currencyCode == "EUR" }?.total == 40)
    }

    @Test func primaryCurrencyFollowsAccountCountAndBreaksTiesByCode() {
        let many = WalletSnapshot(balances: [
            .init(currencyCode: "EUR", total: 10, accountCount: 1),
            .init(currencyCode: "USD", total: 10, accountCount: 3),
        ])
        #expect(many.primaryBalance?.currencyCode == "USD")

        // A tie must resolve the same way every refresh, so the widget never flickers.
        let tied = WalletSnapshot(balances: [
            .init(currencyCode: "USD", total: 10, accountCount: 2),
            .init(currencyCode: "EUR", total: 10, accountCount: 2),
        ])
        #expect(tied.primaryBalance?.currencyCode == "EUR")
    }

    @Test func monthTotalsUsePrimaryCurrencyAndExcludeTransfers() {
        let usd = account("Cash", balance: 0)
        let other = account("Savings", balance: 0)
        let records = [
            record(amount: 30, kind: .expense, account: usd, category: UUID()),
            record(amount: 100, kind: .income, account: usd, category: UUID()),
            record(amount: 500, kind: .transfer, account: usd, destination: other),
        ]
        let snapshot = WalletSnapshotBuilder.make(records: records, accounts: [usd, other],
                                                  categories: [], budgets: [], now: now)

        #expect(snapshot.month?.currencyCode == "USD")
        #expect(snapshot.month?.income == 100)
        #expect(snapshot.month?.expenses == 30)
        #expect(snapshot.month?.net == 70)
    }

    @Test func recentEntriesAreNewestFirstAndCappedWithResolvedTitles() {
        let cash = account("Cash", balance: 0)
        let root = WalletCategory(name: "Food & Drinks")
        let child = WalletCategory(parentID: root.id, name: "Groceries")
        var records = (0..<10).map { record(account: cash, category: child.id, dayOffset: -$0) }
        records.append(record(amount: 5, account: cash, category: nil, dayOffset: 1, payee: "Kiosk"))

        let snapshot = WalletSnapshotBuilder.make(records: records, accounts: [cash],
                                                  categories: [root, child], budgets: [], now: now)

        #expect(snapshot.recent.count == WalletSnapshotBuilder.recentLimit)
        // The newest record is the uncategorized one dated a day ahead of the rest.
        #expect(snapshot.recent.first?.title == "Uncategorized")
        #expect(snapshot.recent.first?.subtitle == "Kiosk")
        #expect(snapshot.recent.first?.colorValue == nil)
        #expect(snapshot.recent[1].title == "Food & Drinks / Groceries")
        #expect(snapshot.recent[1].colorValue == root.colorToken.rawValue)
    }

    @Test func transferEntriesNameBothAccounts() {
        let from = account("Cash", balance: 0)
        let to = account("Savings", balance: 0)
        let snapshot = WalletSnapshotBuilder.make(
            records: [record(amount: 25, kind: .transfer, account: from, destination: to)],
            accounts: [from, to], categories: [], budgets: [], now: now)

        #expect(snapshot.recent.first?.subtitle == "Cash → Savings")
        #expect(snapshot.recent.first?.kind == .transfer)
    }

    @Test func budgetsAreRankedByRatioAndCapped() {
        let cash = account("Cash", balance: 0)
        let category = WalletCategory(name: "Groceries")
        // One 90-unit spend, compared against budgets of different sizes, gives distinct ratios.
        let spending = [record(amount: 90, account: cash, category: category.id)]

        func progress(_ name: String, limit: Decimal) -> BudgetProgress {
            let budget = Budget(name: name, amount: limit, currencyCode: "USD",
                                categoryID: category.id, startDate: now.addingTimeInterval(-1))
            return BudgetProgress.calculate(budget: budget, records: spending, accounts: [cash],
                                            categories: [category], now: now)!
        }
        let budgets = [progress("Low", limit: 300), progress("High", limit: 100),
                       progress("Mid", limit: 200), progress("Over", limit: 60),
                       progress("Tiny", limit: 1000)]

        let snapshot = WalletSnapshotBuilder.make(records: spending, accounts: [cash],
                                                  categories: [category], budgets: budgets, now: now)

        #expect(snapshot.budgets.count == WalletSnapshotBuilder.budgetLimit)
        #expect(snapshot.budgets.map(\.name) == ["Over", "High", "Mid", "Low"])
        #expect(snapshot.budgets.first?.isOverBudget == true)
        #expect(snapshot.budgets.first?.fraction == 1) // clamped for the meter
        #expect(snapshot.budgets.first?.status == "Over budget")
    }

    // MARK: - Store

    @Test func snapshotSurvivesAnEncodeDecodeRoundTripAndOverwrites() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try WalletSnapshotStore.write(.preview, to: url)
        let first = WalletSnapshotStore.read(from: url)
        #expect(first?.balances == WalletSnapshot.preview.balances)
        #expect(first?.recent.count == WalletSnapshot.preview.recent.count)

        // Writing again must replace the existing file rather than fail.
        let replacement = WalletSnapshot(balances: [.init(currencyCode: "GBP", total: 5, accountCount: 1)])
        try WalletSnapshotStore.write(replacement, to: url)
        #expect(WalletSnapshotStore.read(from: url)?.balances.first?.currencyCode == "GBP")
    }

    @Test func readingAMissingOrCorruptSnapshotReturnsNil() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(WalletSnapshotStore.read(from: directory.appendingPathComponent("absent.json")) == nil)

        let corrupt = directory.appendingPathComponent("corrupt.json")
        try Data("not json".utf8).write(to: corrupt)
        #expect(WalletSnapshotStore.read(from: corrupt) == nil)
    }

    // MARK: - Deep links

    @Test func deepLinksRoundTripAndRejectForeignURLs() {
        let links: [WalletDeepLink] = [.home, .records, .statistics, .planning,
                                       .addRecord(.expense), .addRecord(.income), .addRecord(.transfer)]
        for link in links {
            #expect(WalletDeepLink(url: link.url) == link)
        }
        #expect(WalletDeepLink(url: URL(string: "https://example.com/add")!) == nil)
        #expect(WalletDeepLink(url: URL(string: "mywallet://unknown")!) == nil)
        // An add link without a usable kind still opens the editor rather than failing.
        #expect(WalletDeepLink(url: URL(string: "mywallet://add")!) == .addRecord(.expense))
        #expect(WalletDeepLink(url: URL(string: "mywallet://add?kind=nonsense")!) == .addRecord(.expense))
    }
}
