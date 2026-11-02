import Foundation
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

@MainActor
struct BalanceAdjustmentTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func setup() async throws -> (SwiftDataWalletRepository, Account) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let bank = Account(name: "Bank", type: .savings, createdAt: now.addingTimeInterval(-86_400),
                           settings: AccountSettings(currentBalance: 1000))
        try await repository.createAccount(bank)
        return (repository, bank)
    }

    private func balance(_ repository: SwiftDataWalletRepository, _ account: Account) async throws -> Decimal? {
        try await repository.fetchAccounts().first { $0.id == account.id }?.settings.currentBalance
    }

    @Test func increasesAndDecreasesChangeTheBalanceAndAreRecordedWithoutACategory() async throws {
        let (repository, bank) = try await setup()
        let useCases = RecordUseCases(repository: repository)
        var interest = RecordDraft.adjustment(accountID: bank.id, increase: true, amount: Decimal(string: "12.50")!, date: now)
        interest.note = "Interest"
        try await useCases.create(id: UUID(), draft: interest)
        try await useCases.create(id: UUID(), draft: .adjustment(accountID: bank.id, increase: false, amount: 5, date: now))

        #expect(try await balance(repository, bank) == Decimal(string: "1007.50"))
        let saved = try await useCases.load()
        #expect(saved.count == 2)
        #expect(saved.allSatisfy { $0.draft.isAdjustment && $0.draft.categoryID == nil })
        #expect(saved.contains { $0.draft.kind == .income && $0.draft.note == "Interest" })
    }

    @Test func editingAndDeletingAnAdjustmentReversesItsEffect() async throws {
        let (repository, bank) = try await setup()
        let useCases = RecordUseCases(repository: repository)
        let id = UUID()
        try await useCases.create(id: id, draft: .adjustment(accountID: bank.id, increase: true, amount: 40, date: now))
        try await useCases.update(id: id, draft: .adjustment(accountID: bank.id, increase: false, amount: 15, date: now))
        #expect(try await balance(repository, bank) == 985)
        #expect(try await useCases.load().first?.draft.isAdjustment == true)
        try await useCases.delete(id: id)
        #expect(try await balance(repository, bank) == 1000)
    }

    @Test func editingTheAccountBalanceRecordsTheDifferenceAndLeavesEarlierHistory() async throws {
        let (repository, bank) = try await setup()
        let useCases = AccountUseCases(repository: repository)
        var expense = RecordDraft()
        expense.kind = .expense
        expense.accountID = bank.id
        expense.categoryID = try #require(try await repository.fetchCategories().first).id
        expense.amount = 200
        expense.date = now
        try await repository.createRecord(id: UUID(), draft: expense)

        var settings = bank.settings
        settings.currentBalance = 850
        try await useCases.update(id: bank.id, name: "Bank", type: .savings, settings: settings)
        #expect(try await balance(repository, bank) == 850)
        let increase = try #require(try await repository.fetchRecords().first { $0.draft.isAdjustment })
        #expect(increase.draft.kind == .income)
        #expect(increase.draft.amount == 50)

        settings.currentBalance = 800
        try await useCases.update(id: bank.id, name: "Bank", type: .savings, settings: settings)
        #expect(try await balance(repository, bank) == 800)
        let adjustments = try await repository.fetchRecords().filter { $0.draft.isAdjustment }
        #expect(adjustments.count == 2)
        #expect(adjustments.contains { $0.draft.kind == .expense && $0.draft.amount == 50 })

        // Earlier history is untouched: the opening balance is still the one the account began with.
        let account = try #require(try await repository.fetchAccounts().first)
        let statement = AccountStatement.calculate(account: account, records: try await repository.fetchRecords(),
                                                   interval: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(statement.openingBalance == 1000)
    }

    @Test func editingOnlyTheNameRecordsNoAdjustment() async throws {
        let (repository, bank) = try await setup()
        let current = try #require(try await repository.fetchAccounts().first)
        try await AccountUseCases(repository: repository).update(id: bank.id, name: "Main Bank", type: .savings,
                                                                 settings: current.settings)
        #expect(try await repository.fetchRecords().isEmpty)
        #expect(try await repository.fetchAccounts().first?.name == "Main Bank")
    }

    @Test func aTransferCannotBeAnAdjustment() async throws {
        let (repository, bank) = try await setup()
        var draft = RecordDraft.adjustment(accountID: bank.id, increase: true, amount: 10, date: now)
        draft.kind = .transfer
        draft.destinationAccountID = UUID()
        await #expect(throws: RecordValidationError.invalidAdjustment) {
            try await repository.createRecord(id: UUID(), draft: draft)
        }
        #expect(try await balance(repository, bank) == 1000)
    }

    @Test func adjustmentsMoveBalancesButNotIncomeOrExpenseTotals() {
        let bank = Account(name: "Bank", type: .savings, settings: AccountSettings(currentBalance: 1100))
        let category = WalletCategory(name: "Bills")
        var expense = RecordDraft()
        expense.kind = .expense
        expense.accountID = bank.id
        expense.categoryID = category.id
        expense.amount = 30
        expense.date = now
        let records = [
            WalletRecord(id: UUID(), draft: expense, currencyCode: "USD"),
            WalletRecord(id: UUID(), draft: .adjustment(accountID: bank.id, increase: true, amount: 100, date: now),
                         currencyCode: "USD"),
            WalletRecord(id: UUID(), draft: .adjustment(accountID: bank.id, increase: false, amount: 20, date: now),
                         currencyCode: "USD"),
        ]
        let interval = DateInterval(start: now.addingTimeInterval(-3600), duration: 7200)
        let statistics = WalletStatistics.calculate(
            records: records, accounts: [bank], categories: [category],
            filter: StatisticsFilter(interval: interval, currencyCode: "USD"), now: now.addingTimeInterval(3600))
        #expect(statistics.income == 0)
        #expect(statistics.expenses == 30)
        // Opening balance backs out all three records: 1100 + 30 - 100 + 20.
        #expect(statistics.balanceHistory.first?.amount == 1050)
        #expect(statistics.balanceHistory.last?.amount == 1100)

        let activity = AccountActivity(records: records, accountID: bank.id, interval: interval)
        #expect(activity.income == 0)
        #expect(activity.expenses == 30)
        #expect(activity.records.count == 3)

        let statement = AccountStatement.calculate(account: bank, records: records, interval: interval)
        #expect(statement.openingBalance == 1050)
        #expect(statement.closingBalance == 1100)
    }

    @Test func draftsEncodedBeforeAdjustmentsExistedStillDecode() throws {
        var plain = RecordDraft()
        plain.amount = 5
        let encoded = try JSONEncoder().encode(plain)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("adjustment"))
        let decoded = try JSONDecoder().decode(RecordDraft.self, from: encoded)
        #expect(decoded.isAdjustment == false)

        let adjustment = RecordDraft.adjustment(accountID: UUID(), increase: false, amount: 5)
        let roundTripped = try JSONDecoder().decode(RecordDraft.self, from: JSONEncoder().encode(adjustment))
        #expect(roundTripped == adjustment)
        #expect(roundTripped.isAdjustment)
    }

    @Test func csvExportsAdjustmentsByDirectionAndReadsThemBack() throws {
        let bank = Account(name: "Bank", type: .savings)
        let records = [
            WalletRecord(id: UUID(), draft: .adjustment(accountID: bank.id, increase: true, amount: 3, date: now),
                         currencyCode: "USD"),
            WalletRecord(id: UUID(), draft: .adjustment(accountID: bank.id, increase: false, amount: 2,
                                                        date: now.addingTimeInterval(60)),
                         currencyCode: "USD"),
        ]
        let text = RecordCSV.export(records: records, accounts: [bank], categories: [], tags: [])
        #expect(text.contains("adjustment increase"))
        #expect(text.contains("adjustment decrease"))
        let table = try CSV.parse(text)
        let rows = try RecordCSV.rows(from: table, mapping: RecordCSV.mapping(header: table[0]))
        #expect(rows.map(\.kind) == [.income, .expense])
        #expect(rows.allSatisfy { $0.isAdjustment })

        let header = RecordCSVColumn.allCases.filter(\.isRequired).map(\.rawValue)
        let spreadsheet = [header, ["2024-01-01", "Adjustment-Increase", "1", "Bank"]]
        let parsed = try RecordCSV.rows(from: spreadsheet, mapping: RecordCSV.mapping(header: header))
        #expect(parsed.first?.isAdjustment == true)
        #expect(parsed.first?.kind == .income)
    }
}
