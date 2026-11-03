import Foundation
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

/// Bank exports name their columns differently, carry direction in the sign or in separate
/// Debit/Credit columns, give dates without times and usually have no Account column.
struct BankStatementImportTests {
    private func rows(_ csv: String, options: RecordCSVImportOptions = RecordCSVImportOptions(defaultAccountName: "Checking"))
        throws -> [RecordCSVRow] {
        let table = try CSV.parse(csv)
        return try RecordCSV.rows(from: table, mapping: RecordCSV.mapping(header: table[0]), options: options)
    }

    private func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test func signedAmountsWithBankHeadersBecomeExpensesAndIncome() throws {
        // A bank's own Type values ("DEBIT_CARD") are not errors when amounts are signed.
        let parsed = try rows("""
            Details,Posting Date,Description,Amount,Type,Balance
            DEBIT,11/01/2026,COFFEE SHOP,-4.50,DEBIT_CARD,995.50
            CREDIT,11/02/2026,PAYROLL,"2,500.00",ACH_CREDIT,3495.50
            """)

        #expect(parsed.map(\.kind) == [.expense, .income])
        #expect(parsed.map(\.amount) == [Decimal(string: "4.5")!, 2500])
        #expect(parsed.map(\.payee) == ["COFFEE SHOP", "PAYROLL"])
        #expect(parsed.allSatisfy { $0.accountName == "Checking" && $0.isDateOnly && !$0.isAdjustment })
        #expect(components(parsed[0].date).month == 11)
        #expect(components(parsed[0].date).day == 1)
    }

    @Test func debitAndCreditColumnsGiveDirectionAndDayFirstDatesAreDetected() throws {
        let parsed = try rows("""
            Date,Description,Money Out,Money In,Balance
            03/10/2026,Tesco,12.30,,500.00
            13/10/2026,Salary,,"2000.00",2487.70
            """)

        #expect(parsed.map(\.kind) == [.expense, .income])
        #expect(parsed.map(\.amount) == [Decimal(string: "12.3")!, 2000])
        // One day above 12 makes "03/10/2026" read as 3 October, not March 10.
        #expect(components(parsed[0].date).month == 10)
        #expect(components(parsed[0].date).day == 3)
        #expect(components(parsed[1].date).day == 13)
    }

    @Test func debitColumnsWrittenAsNegativeNumbersAreStillSpending() throws {
        let parsed = try rows("""
            Date,Debit,Credit
            2026-11-01,-20.00,
            """)
        #expect(parsed.first?.kind == .expense)
        #expect(parsed.first?.amount == 20)
    }

    @Test func bankTypeValuesSetDirectionWhateverTheSign() throws {
        let parsed = try rows("""
            Transaction Date,Transaction Type,Amount,Memo
            2026-11-01,DR,25.00,Grab ride
            2026-11-02,Credit,-10.00,Refund
            """)

        #expect(parsed.map(\.kind) == [.expense, .income])
        #expect(parsed.map(\.amount) == [25, 10])
        #expect(parsed[0].note == "Grab ride")
    }

    @Test func reversingSignsTurnsPositiveCardChargesIntoExpenses() throws {
        let csv = """
            Date,Description,Amount
            2026-11-01,Bookshop,18.00
            2026-11-02,Payment received,-200.00
            """
        #expect(try rows(csv).map(\.kind) == [.income, .expense])

        let flipped = try rows(csv, options: RecordCSVImportOptions(defaultAccountName: "Card", reversesSigns: true))
        #expect(flipped.map(\.kind) == [.expense, .income])
        #expect(flipped.map(\.amount) == [18, 200])
        #expect(flipped.allSatisfy { $0.accountName == "Card" })
    }

    /// The app's own rows keep their strict checks: the flip never touches them, a negative
    /// amount is still an error, and an unknown Type in an unsigned file is still reported.
    @Test func typedRowsAreNeverFlippedAndKeepTheirChecks() throws {
        let typed = try rows("""
            Date,Type,Amount,Account
            2026-11-01,expense,5,Cash
            """, options: RecordCSVImportOptions(reversesSigns: true))
        #expect(typed.first?.kind == .expense)
        #expect(typed.first?.isDateOnly == true)

        #expect(throws: RecordCSVError.invalidType(row: 2, value: "refund")) {
            try rows("Date,Type,Amount\n2026-11-01,refund,5")
        }
        #expect(throws: RecordCSVError.invalidAmount(row: 2, value: "0.00")) {
            try rows("Date,Amount\n2026-11-01,0.00")
        }
    }

    @Test func aRowWithItsOwnAccountKeepsItAndAnEmptyCellFallsBack() throws {
        let parsed = try rows("""
            Date,Amount,Account
            2026-11-01,-5,Savings
            2026-11-02,-6,
            """)
        #expect(parsed.map(\.accountName) == ["Savings", "Checking"])
    }

    @Test func theAppsOwnHeaderNamesWinOverBankAliases() {
        let mapping = RecordCSV.mapping(header: ["Posting Date", "Description", "Date", "Payee", "Amount"])
        #expect(mapping[.date] == 2)
        #expect(mapping[.payee] == 3)
        #expect(mapping[.amount] == 4)
    }

    @Test func exportsKeepTheirColumnsWithoutDebitOrCredit() throws {
        let text = RecordCSV.export(records: [], accounts: [], categories: [], tags: [])
        #expect(try CSV.parse(text) == [["Date", "Type", "Amount", "Currency", "Account", "To Account", "Category",
                                         "Labels", "Payee", "Note", "Payment Type"]])
    }

    @Test func accountingNegativesAndBankDateFormsParse() {
        #expect(RecordCSV.decimal(from: "(12.34)") == Decimal(string: "-12.34"))
        #expect(RecordCSV.decimal(from: "12.34-") == Decimal(string: "-12.34"))
        #expect(RecordCSV.decimal(from: "-$5") == -5)
        #expect(RecordCSV.decimal(from: "-") == nil)

        #expect(RecordCSV.date(from: "15 Jan 2026") != nil)
        #expect(RecordCSV.date(from: "15-Jan-26") != nil)
        #expect(RecordCSV.date(from: "Jan 15, 2026") != nil)
        #expect(RecordCSV.date(from: "15.01.2026") != nil)
        let twoDigit = RecordCSV.date(from: "01/15/26").map { Calendar.current.component(.year, from: $0) }
        #expect(twoDigit == 2026)
        #expect(RecordCSV.date(from: "03/04/2026", dayFirst: true)
            .map { Calendar.current.component(.month, from: $0) } == 4)
    }
}

/// Bank rows have no time, so two identical purchases on one day are both real.
struct DateOnlyDuplicateTests {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_793_534_400))
    private let checking = Account(name: "Checking", type: .checking)

    private func coffee() -> RecordCSVRow {
        RecordCSVRow(date: day, kind: .expense, amount: 4, accountName: "Checking", isDateOnly: true)
    }

    private func existingCoffee() -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = .expense
        draft.accountID = checking.id
        draft.amount = 4
        draft.date = day
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    private func plan(_ rows: [RecordCSVRow], existing: [WalletRecord]) -> ImportPlan {
        let other = WalletCategory(name: "Other")
        return ImportPlanner.plan(rows: rows, accounts: [checking], categories: [other], tags: [], existing: existing,
                                  fallbackCategoryIDs: [.expense: other.id])
    }

    @Test func identicalDateOnlyRowsInOneFileAreAllImported() {
        #expect(plan([coffee(), coffee()], existing: []).importable.count == 2)
    }

    @Test func uncategorisedRowsTakeTheFallbackForTheirKindOrCannotBeImported() {
        let food = WalletCategory(name: "Food")
        let salary = WalletCategory(name: "Salary")
        let rows = [coffee(),
                    RecordCSVRow(date: day, kind: .income, amount: 900, accountName: "Checking", isDateOnly: true),
                    RecordCSVRow(date: day, kind: .expense, amount: 7, accountName: "Checking",
                                 categoryPath: "Coffee Shops", isDateOnly: true),
                    RecordCSVRow(date: day, kind: .income, amount: 5, accountName: "Checking",
                                 isAdjustment: true, isDateOnly: true)]

        let unchosen = ImportPlanner.plan(rows: rows, accounts: [checking], categories: [food, salary],
                                          tags: [], existing: [])
        #expect(unchosen.entries.map(\.issue) == [.needsCategory(""), .needsCategory(""),
                                                  .needsCategory("Coffee Shops"), nil])
        #expect(unchosen.uncategorizedKinds == [.expense, .income])

        let chosen = ImportPlanner.plan(rows: rows, accounts: [checking], categories: [food, salary], tags: [],
                                        existing: [], fallbackCategoryIDs: [.expense: food.id, .income: salary.id])
        #expect(chosen.importable.count == 4)
        #expect(chosen.entries.map(\.categoryID) == [food.id, salary.id, food.id, nil])
        // Adjustments carry no category, so they never ask for one.
        #expect(chosen.entries.map(\.isUncategorized) == [true, true, true, false])
    }

    @Test func eachExistingRecordAbsorbsOneMatchingRow() {
        let partly = plan([coffee(), coffee()], existing: [existingCoffee()])
        #expect(partly.duplicates.count == 1)
        #expect(partly.importable.count == 1)

        let again = plan([coffee(), coffee()], existing: [existingCoffee(), existingCoffee()])
        #expect(again.duplicates.count == 2)
        #expect(again.importable.isEmpty)
    }
}

@MainActor
struct BankStatementImportViewModelTests {
    private let statement = """
        Date,Description,Amount
        2026-11-01,Bookshop,18.00
        2026-11-02,Refund,-3.00
        """

    private func make() async throws -> (DataExchangeViewModel, RecordsViewModel) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        try await AccountUseCases(repository: repository).create(name: "Checking", type: .checking, currencyCode: "MMK")
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository),
                                       accounts: AccountUseCases(repository: repository),
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        await records.reload()
        let viewModel = DataExchangeViewModel(records: records, recordUseCases: RecordUseCases(repository: repository),
                                              tagUseCases: TagUseCases(repository: repository))
        return (viewModel, records)
    }

    @Test func aStatementWithoutAccountsAsksForOneThenPlansAndImportsIntoIt() async throws {
        let (viewModel, records) = try await make()

        viewModel.prepareImport(text: statement)
        #expect(viewModel.needsAccountChoice)
        #expect(viewModel.plan == nil)
        #expect(viewModel.accountNames == ["Checking"])

        viewModel.chooseImportAccount("Checking")
        #expect(!viewModel.needsAccountChoice)
        #expect(viewModel.canReverseSigns)
        // Uncategorised income starts in the starter Income category; spending waits for a choice.
        let income = try #require(records.categories.first { $0.parentID == nil && $0.name == "Income" })
        #expect(viewModel.fallbackCategoryIDs == [.income: income.id])
        let plan = try #require(viewModel.plan)
        #expect(plan.entries.map(\.row.kind) == [.income, .expense])
        #expect(plan.importable.map(\.row.payee) == ["Bookshop"])
        #expect(plan.problems.map(\.issue) == [.needsCategory("")])
        #expect(plan.uncategorizedKinds == [.income, .expense])
        #expect(viewModel.currencyCode(for: plan.importable[0]) == "MMK")
        #expect(viewModel.previewTitle(for: plan.importable[0]) == "Bookshop")

        viewModel.setReversesSigns(true)
        #expect(viewModel.plan?.importable.map(\.row.payee) == ["Refund"])
        let shopping = try #require(records.categories.first { $0.parentID == nil && $0.name == "Shopping" })
        viewModel.setFallbackCategory(shopping.id, for: .expense)
        #expect(viewModel.plan?.importable.map(\.row.kind) == [.expense, .income])
        #expect(viewModel.plan?.importable.map(\.categoryID) == [shopping.id, income.id])

        await viewModel.applyImport()
        #expect(viewModel.importedCount == 2)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.plan == nil)
        #expect(viewModel.importOptions == RecordCSVImportOptions())
        #expect(viewModel.fallbackCategoryIDs.isEmpty)
        let saved = records.records.sorted { $0.draft.date < $1.draft.date }
        #expect(saved.map(\.draft.kind) == [.expense, .income])
        #expect(saved.map(\.draft.categoryID) == [shopping.id, income.id])
        #expect(saved.map(\.draft.payee) == ["Bookshop", "Refund"])

        // The same statement again is entirely recognised, before any category is chosen.
        viewModel.prepareImport(text: statement)
        viewModel.chooseImportAccount("Checking")
        viewModel.setReversesSigns(true)
        #expect(viewModel.plan?.duplicates.count == 2)
        #expect(viewModel.plan?.uncategorizedKinds.isEmpty == true)
    }

    @Test func aFileMissingOtherColumnsFailsBeforeAskingForAnAccount() async throws {
        let (viewModel, _) = try await make()
        viewModel.prepareImport(text: "Description,Amount\nBookshop,18")

        #expect(!viewModel.needsAccountChoice)
        #expect(viewModel.plan == nil)
        #expect(viewModel.errorMessage == RecordCSVError.missingColumns([.date]).errorDescription)
    }

    @Test func cancellingTheAccountChoiceClearsThePendingFile() async throws {
        let (viewModel, _) = try await make()
        viewModel.prepareImport(text: statement)
        viewModel.cancelImport()

        #expect(!viewModel.needsAccountChoice)
        viewModel.chooseImportAccount("Checking")
        #expect(viewModel.plan == nil)
    }
}
