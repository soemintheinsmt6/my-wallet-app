import Foundation
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

struct PayeeSuggestionsTests {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_793_534_400))

    private func record(_ payee: String, kind: RecordKind = .expense, daysAgo: Int = 0,
                        adjustment: Bool = false) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.amount = 5
        draft.payee = payee
        draft.isAdjustment = adjustment
        draft.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: day)!
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    @Test func typedTextMatchesTheStartOfAPayeeOrOfAnyWordInIt() {
        let payees = PayeeSuggestions(records: [record("Starbucks"), record("Blue Bottle Coffee"),
                                                record("7-Eleven"), record("Costa")])

        #expect(payees.suggestions(for: "star", kind: .expense) == ["Starbucks"])
        #expect(payees.suggestions(for: "COF", kind: .expense) == ["Blue Bottle Coffee"])
        #expect(payees.suggestions(for: "ele", kind: .expense) == ["7-Eleven"])
        #expect(payees.suggestions(for: "ucks", kind: .expense).isEmpty)
        #expect(payees.suggestions(for: "blue bo", kind: .expense) == ["Blue Bottle Coffee"])
    }

    @Test func accentsAndCaseAreIgnored() {
        let payees = PayeeSuggestions(records: [record("Café Nero")])
        #expect(payees.suggestions(for: "cafe", kind: .expense) == ["Café Nero"])
    }

    @Test func spellingsOfOnePayeeAreOfferedOnceUnderTheMostUsed() {
        let payees = PayeeSuggestions(records: [record("Starbucks", daysAgo: 9), record("Starbucks", daysAgo: 5),
                                                record("STARBUCKS #0042", daysAgo: 1), record("STARBUCKS #0051")])
        #expect(payees.suggestions(for: "sta", kind: .expense) == ["Starbucks"])
    }

    @Test func payeesItStartsComeFirstThenTheMostUsed() {
        let payees = PayeeSuggestions(records: [record("Coffee Club"), record("Blue Bottle Coffee"),
                                                record("Blue Bottle Coffee"), record("Arabica Coffee"),
                                                record("Arabica Coffee"), record("Arabica Coffee")])
        #expect(payees.suggestions(for: "coffee", kind: .expense)
                == ["Coffee Club", "Arabica Coffee", "Blue Bottle Coffee"])
    }

    @Test func withNothingTypedTheMostRecentAreOfferedUpToTheLimit() {
        let names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf"]
        // Golf is the oldest however often it was used.
        let payees = PayeeSuggestions(records: names.enumerated().map { record($1, daysAgo: $0) }
                                      + [record("Golf", daysAgo: 30)])
        #expect(payees.suggestions(for: " ", kind: .expense) == Array(names.prefix(5)))
        #expect(payees.suggestions(for: "", kind: .expense, limit: 2) == ["Alpha", "Bravo"])
    }

    @Test func theTypedPayeeIsNotOfferedBack() {
        let payees = PayeeSuggestions(records: [record("Grab"), record("Grab Food")])
        #expect(payees.suggestions(for: "grab", kind: .expense) == ["Grab Food"])
    }

    @Test func theRecordsOwnKindComesFirstAndOtherKindsFillTheRest() {
        let payees = PayeeSuggestions(records: [record("Acme Ltd", kind: .income, daysAgo: 9),
                                                record("Acme Cafe", daysAgo: 1), record("Acme Hardware", daysAgo: 0)])

        // The employer leads for income, though the shops were used more recently.
        #expect(payees.suggestions(for: "ac", kind: .income) == ["Acme Ltd", "Acme Hardware", "Acme Cafe"])
        #expect(payees.suggestions(for: "", kind: .income) == ["Acme Ltd", "Acme Hardware", "Acme Cafe"])
        #expect(payees.suggestions(for: "ac", kind: .expense) == ["Acme Hardware", "Acme Cafe", "Acme Ltd"])
        #expect(payees.suggestions(for: "ac", kind: .income, limit: 1) == ["Acme Ltd"])
    }

    @Test func incomeWithoutPayersOfItsOwnStillOffersPayeesInTheWallet() {
        let payees = PayeeSuggestions(records: [record("Starbucks"), record("Grab")])
        #expect(payees.suggestions(for: "gr", kind: .income) == ["Grab"])
        #expect(payees.suggestions(for: "", kind: .income).count == 2)
    }

    @Test func aPayeeRecordedUnderTwoKindsIsOfferedOnce() {
        let payees = PayeeSuggestions(records: [record("Mom"), record("Mom", kind: .income)])
        #expect(payees.suggestions(for: "", kind: .income) == ["Mom"])
    }

    @Test func adjustmentsAndBlanksAreLeftOut() {
        let payees = PayeeSuggestions(records: [record("Bank", adjustment: true), record("   "), record(" Grab ")])
        #expect(payees.suggestions(for: "", kind: .expense) == ["Grab"])
    }
}

@MainActor
struct PayeeSuggestionsViewModelTests {
    @Test func aSavedRecordsPayeeIsOfferedWithoutAReload() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accounts = AccountUseCases(repository: repository)
        try await accounts.create(name: "Checking", type: .checking, currencyCode: "USD")
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: accounts,
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        await records.reload()
        #expect(records.payeeSuggestions(for: "", kind: .expense).isEmpty)

        var draft = RecordDraft()
        draft.accountID = try #require(records.accounts.first).id
        draft.amount = 5
        draft.categoryID = try #require(records.categories.first).id
        draft.payee = "Starbucks"
        try await records.save(id: UUID(), draft: draft)

        #expect(records.payeeSuggestions(for: "st", kind: .expense) == ["Starbucks"])
    }

    /// The editor builds the payee data in the background when it opens; a record saved after
    /// that build must still be offered, so the change drops what was built.
    @Test func dataBuiltInTheBackgroundFollowsLaterSaves() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accounts = AccountUseCases(repository: repository)
        try await accounts.create(name: "Checking", type: .checking, currencyCode: "USD")
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: accounts,
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        await records.reload()
        let category = try #require(records.categories.first)

        var draft = RecordDraft()
        draft.accountID = try #require(records.accounts.first).id
        draft.amount = 5
        draft.categoryID = category.id
        draft.payee = "Grab"
        try await records.save(id: UUID(), draft: draft)
        await records.preparePayeeData()
        #expect(records.payeeSuggestions(for: "", kind: .expense) == ["Grab"])
        #expect(records.learnedCategory(forPayee: "GRAB TRIP", kind: .expense) == category.id)

        draft.payee = "Starbucks"
        try await records.save(id: UUID(), draft: draft)
        #expect(records.payeeSuggestions(for: "st", kind: .expense) == ["Starbucks"])
        #expect(records.learnedCategory(forPayee: "Starbucks", kind: .expense) == category.id)
    }
}
