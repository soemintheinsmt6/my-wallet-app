import Foundation
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

struct PayeeCategorizerTests {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_793_534_400))
    private let checking = Account(name: "Checking", type: .checking)
    private let coffee = WalletCategory(name: "Coffee")
    private let transport = WalletCategory(name: "Transport")
    private let salary = WalletCategory(name: "Salary")
    private let other = WalletCategory(name: "Other")
    private var categories: [WalletCategory] { [coffee, transport, salary, other] }

    private func record(_ payee: String, _ category: WalletCategory?, kind: RecordKind = .expense,
                        daysAgo: Int = 0, adjustment: Bool = false) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = checking.id
        draft.amount = 5
        draft.categoryID = category?.id
        draft.payee = payee
        draft.isAdjustment = adjustment
        draft.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: day)!
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    private func categorizer(_ records: [WalletRecord]) -> PayeeCategorizer {
        PayeeCategorizer(records: records, categories: categories)
    }

    @Test func bankDescriptionsMatchPayeesTypedByHand() {
        let learned = categorizer([record("Starbucks", coffee), record("Grab", transport)])

        #expect(learned.category(forPayee: "STARBUCKS #1234", kind: .expense) == coffee.id)
        #expect(learned.category(forPayee: "POS STARBUCKS 0042", kind: .expense) == coffee.id)
        #expect(learned.category(forPayee: "GRAB*TRIP SINGAPORE SG", kind: .expense) == transport.id)
        #expect(learned.category(forPayee: "  grab  ", kind: .expense) == transport.id)
        #expect(learned.category(forPayee: "Grabbing Lunch", kind: .expense) == nil)
        #expect(learned.category(forPayee: "", kind: .expense) == nil)
    }

    @Test func accentsAndNonLatinPayeesAreMatched() {
        let learned = categorizer([record("Café Nero", coffee), record("ရွှေလမင်း", coffee)])

        #expect(learned.category(forPayee: "CAFE NERO LONDON", kind: .expense) == coffee.id)
        #expect(learned.category(forPayee: "ရွှေလမင်း", kind: .expense) == coffee.id)
    }

    @Test func theLongestKnownStartOfADescriptionWins() {
        let learned = categorizer([record("Grab", transport), record("Grab Food", other)])

        #expect(learned.category(forPayee: "GRAB FOOD 8812 SG", kind: .expense) == other.id)
        #expect(learned.category(forPayee: "GRAB TRIP", kind: .expense) == transport.id)
    }

    @Test func theMostRecentRecordForAPayeeWins() {
        let learned = categorizer([record("Starbucks", other, daysAgo: 1), record("Starbucks", coffee, daysAgo: 0),
                                   record("Starbucks", other, daysAgo: 30)])
        #expect(learned.category(forPayee: "Starbucks", kind: .expense) == coffee.id)
    }

    @Test func incomeAndSpendingAreLearnedSeparately() {
        let learned = categorizer([record("Acme Ltd", salary, kind: .income)])

        #expect(learned.category(forPayee: "ACME LTD", kind: .income) == salary.id)
        #expect(learned.category(forPayee: "ACME LTD", kind: .expense) == nil)
    }

    @Test func transfersAdjustmentsUncategorisedAndDeletedCategoriesTeachNothing() {
        let deleted = WalletCategory(name: "Gone")
        let learned = categorizer([record("Bank", other, kind: .transfer), record("Interest", other, adjustment: true),
                                   record("Shop", nil), record("Kiosk", deleted)])

        #expect(learned.isEmpty)
        #expect(learned.category(forPayee: "Kiosk", kind: .expense) == nil)
    }

    @Test func processorWordsAloneNameNoPayee() {
        #expect(PayeeCategorizer.key(for: "CARD PAYMENT 0042") == "")
        #expect(PayeeCategorizer.key(for: "PAYPAL *SPOTIFY") == "spotify")
        #expect(categorizer([record("Card payment", other)]).isEmpty)
    }

    @Test func importRowsWithoutACategoryTakeTheLearnedOneBeforeTheFallback() {
        let rows = [RecordCSVRow(date: day, kind: .expense, amount: 4, accountName: "Checking",
                                 payee: "STARBUCKS #12", isDateOnly: true),
                    RecordCSVRow(date: day, kind: .expense, amount: 9, accountName: "Checking",
                                 payee: "Hardware Store", isDateOnly: true),
                    RecordCSVRow(date: day, kind: .expense, amount: 6, accountName: "Checking",
                                 categoryPath: "Transport", payee: "Starbucks", isDateOnly: true)]
        let existing = [record("Starbucks", coffee, daysAgo: 10)]

        let plan = ImportPlanner.plan(rows: rows, accounts: [checking], categories: categories, tags: [],
                                      existing: existing, fallbackCategoryIDs: [.expense: other.id],
                                      categorizer: categorizer(existing))

        #expect(plan.entries.map(\.categoryID) == [coffee.id, other.id, transport.id])
        #expect(plan.entries.map(\.hasLearnedCategory) == [true, false, false])
        // Only the unknown payee still needs the fallback.
        #expect(plan.entries.map(\.isUncategorized) == [false, true, false])
        #expect(plan.learnedCategoryCount == 1)

        let unchosen = ImportPlanner.plan(rows: Array(rows.prefix(1)), accounts: [checking], categories: categories,
                                          tags: [], existing: existing, categorizer: categorizer(existing))
        #expect(unchosen.importable.count == 1)
        #expect(unchosen.uncategorizedKinds.isEmpty)
    }
}

@MainActor
struct PayeeCategorizerViewModelTests {
    private let statement = """
        Date,Description,Amount
        2026-11-01,STARBUCKS #0042,-4.50
        2026-11-02,New Shop,-8.00
        """

    @Test func anImportFilesKnownPayeesAndCanBeToldNotTo() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accounts = AccountUseCases(repository: repository)
        try await accounts.create(name: "Checking", type: .checking, currencyCode: "USD")
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: accounts,
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        await records.reload()
        let food = try #require(records.categories.first { $0.parentID == nil && $0.name == "Food & Drinks" }
                                ?? records.categories.first { $0.parentID == nil && $0.name != "Income" })
        let shopping = try #require(records.categories.first { $0.parentID == nil && $0.id != food.id && $0.name != "Income" })
        var draft = RecordDraft()
        draft.accountID = try #require(records.accounts.first).id
        draft.amount = 5
        draft.categoryID = food.id
        draft.payee = "Starbucks"
        draft.date = Date(timeIntervalSince1970: 1_793_000_000)
        try await records.save(id: UUID(), draft: draft)
        // The cache follows the saved record without a reload.
        #expect(records.learnedCategory(forPayee: "STARBUCKS #0042", kind: .expense) == food.id)

        let viewModel = DataExchangeViewModel(records: records, recordUseCases: RecordUseCases(repository: repository),
                                              tagUseCases: TagUseCases(repository: repository))
        viewModel.prepareImport(text: statement)
        viewModel.chooseImportAccount("Checking")
        viewModel.setFallbackCategory(shopping.id, for: .expense)
        var plan = try #require(viewModel.plan)
        #expect(plan.importable.map(\.categoryID) == [food.id, shopping.id])
        #expect(plan.learnedCategoryCount == 1)
        #expect(viewModel.previewTitle(for: plan.importable[0]) == "STARBUCKS #0042")
        #expect(viewModel.previewCategory(for: plan.importable[0]) == food.name)

        viewModel.setUsesLearnedCategories(false)
        plan = try #require(viewModel.plan)
        #expect(plan.importable.map(\.categoryID) == [shopping.id, shopping.id])
        #expect(plan.learnedCategoryCount == 0)

        viewModel.setUsesLearnedCategories(true)
        await viewModel.applyImport()
        #expect(viewModel.importedCount == 2)
        #expect(viewModel.usesLearnedCategories)
        let imported = records.records.filter { $0.draft.payee != "Starbucks" }.sorted { $0.draft.date < $1.draft.date }
        #expect(imported.map(\.draft.categoryID) == [food.id, shopping.id])
    }
}
