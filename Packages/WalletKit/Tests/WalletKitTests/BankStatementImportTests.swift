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

    /// `seed` writes records into the Checking account (passed by ID) before the wallet loads.
    private func make(seed: (SwiftDataWalletRepository, UUID) async throws -> Void = { _, _ in })
        async throws -> (DataExchangeViewModel, RecordsViewModel) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        try await AccountUseCases(repository: repository).create(name: "Checking", type: .checking, currencyCode: "MMK")
        try await seed(repository, try #require(try await repository.fetchAccounts().first).id)
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

    /// A purchase typed in by hand two days before the bank posted it is recognised, and a wrong
    /// match can be overridden until the import is cancelled.
    @Test func aManualEntryIsMatchedAndCanBeImportedAnyway() async throws {
        let enteredAt = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30,
                                                                                 hour: 14, minute: 32)))
        let (viewModel, _) = try await make { repository, accountID in
            let category = try #require(try await repository.fetchCategories().first { $0.parentID != nil })
            var draft = RecordDraft()
            draft.kind = .expense
            draft.accountID = accountID
            draft.amount = 18
            draft.categoryID = category.id
            draft.date = enteredAt
            try await RecordUseCases(repository: repository).create(id: UUID(), draft: draft)
        }

        viewModel.prepareImport(text: statement)
        viewModel.chooseImportAccount("Checking")
        viewModel.setReversesSigns(true)
        let matched = try #require(viewModel.plan?.matchedToRecords.first)
        #expect(viewModel.plan?.matchedToRecords.count == 1)
        #expect(matched.row.payee == "Bookshop")
        #expect(matched.matchedRecordDate == enteredAt)
        #expect(viewModel.plan?.importable.map(\.row.payee) == ["Refund"])

        viewModel.importAnyway(matched)
        #expect(viewModel.unmatchedRowIndices == [matched.rowIndex])
        #expect(viewModel.plan?.matchedToRecords.isEmpty == true)
        #expect(viewModel.plan?.duplicates.isEmpty == true)

        viewModel.cancelImport()
        #expect(viewModel.unmatchedRowIndices.isEmpty)
    }
}

/// Bringing matched records to the bank's amount when the import is applied.
@MainActor
struct TipImportViewModelTests {
    private let statement = """
        Date,Description,Amount
        2026-11-05,Dinner,-60.00
        """
    private let photo = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])

    /// A wallet with a 50 dinner entered by hand the day before the bank's 60 charge, with a receipt photo.
    private func make(split: Bool = false)
        async throws -> (DataExchangeViewModel, RecordsViewModel, SwiftDataWalletRepository, UUID) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        try await AccountUseCases(repository: repository).create(name: "Checking", type: .checking)
        let accountID = try #require(try await repository.fetchAccounts().first).id
        let category = try #require(try await repository.fetchCategories().first { $0.parentID != nil })
        var draft = RecordDraft()
        draft.kind = .expense
        draft.accountID = accountID
        draft.amount = 50
        draft.categoryID = category.id
        draft.payee = "Noodle House"
        draft.photoData = photo
        draft.date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 20)))
        let dinnerID = UUID()
        try await RecordUseCases(repository: repository).create(id: dinnerID, draft: draft)
        if split {
            let shares = [SplitParticipant(name: "Me", share: 25, paid: 50), SplitParticipant(name: "Aye", share: 25)]
            try await SplitUseCases(repository: repository)
                .save(RecordSplit(recordID: dinnerID, method: .equally, participants: shares), recordAmount: 50)
        }

        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository),
                                       accounts: AccountUseCases(repository: repository),
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        await records.reload()
        let viewModel = DataExchangeViewModel(records: records, recordUseCases: RecordUseCases(repository: repository),
                                              tagUseCases: TagUseCases(repository: repository),
                                              splitUseCases: SplitUseCases(repository: repository))
        viewModel.prepareImport(text: statement)
        viewModel.chooseImportAccount("Checking")
        return (viewModel, records, repository, dinnerID)
    }

    private func dinner(_ records: RecordsViewModel, _ id: UUID) -> WalletRecord? {
        records.records.first { $0.id == id }
    }

    @Test func aTippedBillTakesTheBankAmountAndKeepsItsPhotoAndDetails() async throws {
        let (viewModel, records, repository, dinnerID) = try await make()
        let plan = try #require(viewModel.plan)
        #expect(plan.importable.isEmpty)
        #expect(plan.matchedToRecords.first?.match?.kind == .tip)
        #expect(viewModel.pendingAmountUpdates.count == 1)

        await viewModel.applyImport()
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.importedCount == 0)
        #expect(viewModel.updatedCount == 1)
        let updated = try #require(dinner(records, dinnerID))
        #expect(updated.draft.amount == 60)
        #expect(updated.draft.payee == "Noodle House")
        #expect(records.records.count == 1)
        // Loaded records carry no photo bytes; the update must not have erased the receipt.
        #expect(try await RecordUseCases(repository: repository).photo(id: dinnerID) == photo)
        #expect(records.accounts.first?.settings.currentBalance == -60)
    }

    @Test func turningUpdatesOffLeavesTheRecordAsEntered() async throws {
        let (viewModel, records, _, dinnerID) = try await make()
        viewModel.setUpdatesMatchedAmounts(false)
        #expect(viewModel.pendingAmountUpdates.isEmpty)

        await viewModel.applyImport()
        #expect(viewModel.updatedCount == 0)
        #expect(dinner(records, dinnerID)?.draft.amount == 50)
        #expect(viewModel.updatesMatchedAmounts)
    }

    @Test func aSplitBillKeepsItsAmountAndIsReported() async throws {
        let (viewModel, records, repository, dinnerID) = try await make(split: true)
        await viewModel.applyImport()

        #expect(viewModel.updatedCount == 0)
        #expect(viewModel.keptSplitCount == 1)
        #expect(viewModel.errorMessage == nil)
        #expect(dinner(records, dinnerID)?.draft.amount == 50)
        let split = try #require(try await repository.fetchSplits().first)
        #expect(split.total == 50)
    }
}

/// Bank rows matched by day against records entered by hand, which carry a time of day and are
/// often dated before the bank posts them.
struct ManualEntryMatchingTests {
    private let checking = Account(name: "Checking", type: .checking)
    private let savings = Account(name: "Savings", type: .savings)

    private func day(_ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func bankRow(_ day: Int, _ kind: RecordKind = .expense, amount: Decimal = 4,
                         account: String = "Checking") -> RecordCSVRow {
        RecordCSVRow(date: self.day(day), kind: kind, amount: amount, accountName: account, isDateOnly: true)
    }

    private func entered(_ day: Int, hour: Int = 15, _ kind: RecordKind = .expense, amount: Decimal = 4,
                         account: Account? = nil, to destination: Account? = nil, received: Decimal? = nil) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = (account ?? checking).id
        draft.destinationAccountID = destination?.id
        draft.receivedAmount = received
        draft.amount = amount
        draft.date = self.day(day, hour: hour)
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    private func plan(_ rows: [RecordCSVRow], _ existing: [WalletRecord], unmatched: Set<Int> = []) -> ImportPlan {
        let other = WalletCategory(name: "Other")
        return ImportPlanner.plan(rows: rows, accounts: [checking, savings], categories: [other], tags: [],
                                  existing: existing, fallbackCategoryIDs: [.expense: other.id, .income: other.id],
                                  unmatchedRowIndices: unmatched)
    }

    @Test func aRecordEnteredAtAnyTimeThatDayMatches() {
        let result = plan([bankRow(5)], [entered(5, hour: 23)])
        #expect(result.duplicates.count == 1)
        #expect(result.entries[0].matchedRecordDate == day(5, hour: 23))
    }

    @Test func recordsUpToThePostingLagEarlierMatchButNotLaterOrOlderOnes() {
        #expect(plan([bankRow(5)], [entered(2)]).duplicates.count == 1)
        #expect(plan([bankRow(5)], [entered(1)]).duplicates.isEmpty)
        // The bank never posts before the purchase.
        #expect(plan([bankRow(5)], [entered(6)]).duplicates.isEmpty)
    }

    @Test func accountDirectionAndAmountMustAllAgree() {
        let existing = [entered(5)]
        // 50% above the 4 entered: beyond even a tip.
        #expect(plan([bankRow(5, amount: 6)], existing).duplicates.isEmpty)
        #expect(plan([bankRow(5, .income)], existing).duplicates.isEmpty)
        #expect(plan([bankRow(5, account: "Savings")], existing).duplicates.isEmpty)
    }

    /// Matching row by row would hand the 2 Nov record to the 3 Nov row (one day of lag) and
    /// leave the 2 Nov row unmatched; exact days are settled first.
    @Test func sameDayMatchesAreMadeBeforeLaggedOnes() {
        let result = plan([bankRow(3), bankRow(2)], [entered(2)])
        #expect(result.entries.map(\.issue) == [nil, .duplicate])
    }

    @Test func theClosestEarlierRecordIsMatched() {
        let result = plan([bankRow(4)], [entered(1), entered(3)])
        #expect(result.entries[0].matchedRecordDate == day(3, hour: 15))
    }

    @Test func aTransferEnteredByHandMatchesBothAccountsStatements() {
        // Sent in one currency, received as 80 in the other.
        let transfer = entered(5, .transfer, amount: 100, to: savings, received: 80)
        let result = plan([bankRow(6, amount: 100), bankRow(6, .income, amount: 80, account: "Savings")], [transfer])
        #expect(result.duplicates.count == 2)
        // The source leg is not money in, and the destination receives the received amount.
        #expect(plan([bankRow(6, .income, amount: 100, account: "Savings")], [transfer]).duplicates.isEmpty)
    }

    private func amount(_ text: String) -> Decimal { Decimal(string: text)! }

    @Test func anAmountWithinFivePercentMatchesAndReportsWhatWasEntered() {
        // A card charge entered as 100 that settled at 103.50 after a foreign-transaction fee.
        let result = plan([bankRow(5, amount: amount("103.50"))], [entered(4, amount: 100)])
        #expect(result.duplicates.count == 1)
        #expect(result.entries[0].matchedRecordAmount == 100)
        #expect(result.entries[0].differingMatchedAmount == 100)

        // 5.5% less than entered: outside the tolerance, and a tip only ever adds.
        #expect(plan([bankRow(5, amount: amount("94.50"))], [entered(4, amount: 100)]).duplicates.isEmpty)
        // An exact match reports no difference.
        #expect(plan([bankRow(5)], [entered(5)]).entries[0].differingMatchedAmount == nil)
    }

    @Test func anExactAmountWithinTheLagBeatsANearAmountOnTheSameDay() {
        let near = entered(5, amount: amount("4.10"))
        let exact = entered(3)
        let result = plan([bankRow(5)], [near, exact])
        #expect(result.entries[0].matchedRecordDate == day(3, hour: 15))
        #expect(result.entries[0].matchedRecordAmount == 4)
    }

    /// The near row comes first in the file but must not take the record the exact row matches.
    @Test func aRowsExactMatchIsNotTakenByAnotherRowsNearMatch() {
        let result = plan([bankRow(5, amount: amount("4.10")), bankRow(5)], [entered(5)])
        #expect(result.entries.map(\.issue) == [nil, .duplicate])
    }

    @Test func amongNearAmountsTheClosestIsMatched() {
        let result = plan([bankRow(5)], [entered(5, amount: amount("4.15")), entered(5, amount: amount("3.95"))])
        #expect(result.entries[0].matchedRecordAmount == amount("3.95"))
    }

    @Test func aTransfersReceivedAmountMatchesWithinTheTolerance() {
        let transfer = entered(5, .transfer, amount: 100, to: savings, received: 98)
        let result = plan([bankRow(5, .income, amount: amount("97.20"), account: "Savings")], [transfer])
        #expect(result.entries[0].matchedRecordAmount == 98)
    }

    @Test func aTipOfUpToAQuarterMatchesAndUpdatesTheBill() {
        let result = plan([bankRow(5, amount: 60)], [entered(4, amount: 50)])
        #expect(result.entries[0].match?.kind == .tip)
        #expect(result.entries[0].amountUpdate?.field == .amount)
        #expect(result.entries[0].amountUpdate?.from == 50)
        #expect(result.entries[0].amountUpdate?.to == 60)
        #expect(result.amountUpdates.count == 1)

        #expect(plan([bankRow(5, amount: amount("62.60"))], [entered(4, amount: 50)]).duplicates.isEmpty)
        // A tip only adds: a bank charge 20% below the bill is something else.
        #expect(plan([bankRow(5, amount: 40)], [entered(4, amount: 50)]).duplicates.isEmpty)
    }

    @Test func tipsApplyOnlyToBillsNotIncomeTransfersOrAdjustments() {
        #expect(plan([bankRow(5, .income, amount: 60)], [entered(5, .income, amount: 50)]).duplicates.isEmpty)
        #expect(plan([bankRow(5, amount: 60)], [entered(5, .transfer, amount: 50, to: savings)]).duplicates.isEmpty)
        var adjustment = entered(5, amount: 50)
        var draft = adjustment.draft
        draft.isAdjustment = true
        adjustment = WalletRecord(id: adjustment.id, draft: draft, currencyCode: "USD")
        #expect(plan([bankRow(5, amount: 60)], [adjustment]).duplicates.isEmpty)
    }

    /// The bill's own bank row takes it first, so a different, larger purchase is not read as a tip on it.
    @Test func aBillsExactRowIsMatchedBeforeAnyTip() {
        let result = plan([bankRow(5, amount: 60), bankRow(5, amount: 50)], [entered(5, amount: 50)])
        #expect(result.entries.map(\.issue) == [nil, .duplicate])
        #expect(result.amountUpdates.isEmpty)
    }

    @Test func aNearAmountIsPreferredOverATip() {
        let result = plan([bankRow(5, amount: 60)], [entered(5, amount: 50), entered(5, amount: 58)])
        #expect(result.entries[0].match?.kind == .near)
        #expect(result.entries[0].matchedRecordAmount == 58)
    }

    @Test func nearMatchesUpdateTheAmountButASameCurrencyTransferKeepsIt() throws {
        let charge = entered(4, amount: 100)
        let update = try #require(plan([bankRow(5, amount: amount("103.50"))], [charge]).amountUpdates.first)
        #expect(update == ImportPlan.AmountUpdate(recordID: charge.id, field: .amount, from: 100, to: amount("103.50")))
        // Exact matches change nothing.
        #expect(plan([bankRow(5)], [entered(5)]).amountUpdates.isEmpty)

        // Checking and Savings share a currency, so one statement cannot change one side alone.
        let transfer = entered(5, .transfer, amount: 100, to: savings)
        let sameCurrency = plan([bankRow(5, .income, amount: 98, account: "Savings")], [transfer])
        #expect(sameCurrency.duplicates.count == 1)
        #expect(sameCurrency.amountUpdates.isEmpty)
    }

    @Test func aCrossCurrencyTransferUpdatesTheSideTheStatementShows() {
        let euros = Account(name: "Euros", type: .savings, currencyCode: "EUR")
        let transfer = entered(5, .transfer, amount: 100, to: euros, received: 92)
        let result = ImportPlanner.plan(
            rows: [bankRow(5, .income, amount: 91, account: "Euros"), bankRow(5, amount: 101)],
            accounts: [checking, euros], categories: [], tags: [], existing: [transfer])
        #expect(result.amountUpdates.map(\.field) == [.receivedAmount, .amount])
        #expect(result.amountUpdates.map(\.to) == [91, 101])

        var draft = transfer.draft
        result.amountUpdates.forEach { $0.apply(to: &draft) }
        #expect(draft.amount == 101)
        #expect(draft.receivedAmount == 91)
    }

    @Test func importingAnywayFreesTheRecordForAnotherRow() {
        let rows = [bankRow(5), bankRow(5)]
        #expect(plan(rows, [entered(5)]).entries.map(\.issue) == [.duplicate, nil])
        #expect(plan(rows, [entered(5)], unmatched: [0]).entries.map(\.issue) == [nil, .duplicate])
    }
}
