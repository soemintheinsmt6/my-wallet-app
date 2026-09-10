import Foundation
import Testing
import WalletData
import WalletDomain
@testable import WalletFeature

struct SplitCalculatorTests {
    /// Splitting 10 three ways cannot be 3.33 each — that loses a cent.
    @Test func equalSharesAlwaysAddBackToTheExactTotal() {
        let shares = SplitCalculator.equalShares(total: 10, count: 3)
        #expect(shares.reduce(0, +) == 10)
        #expect(shares == [Decimal(string: "3.34"), Decimal(string: "3.33"), Decimal(string: "3.33")])
    }

    @Test func equalSharesDivideCleanlyWhenTheyCan() {
        let shares = SplitCalculator.equalShares(total: 100, count: 4)
        #expect(shares.allSatisfy { $0 == 25 })
        #expect(shares.reduce(0, +) == 100)
    }

    /// Zero-decimal currencies must not gain fractions of a yen.
    @Test func equalSharesRespectZeroDecimalCurrencies() {
        let shares = SplitCalculator.equalShares(total: 1000, count: 3, currencyCode: "JPY")
        #expect(shares.reduce(0, +) == 1000)
        #expect(shares == [334, 333, 333])
    }

    @Test func equalSharesHandleEdgeCounts() {
        #expect(SplitCalculator.equalShares(total: 10, count: 0).isEmpty)
        #expect(SplitCalculator.equalShares(total: 10, count: 1) == [10])
    }

    @Test func percentagesConvertToAmountsThatSumExactly() throws {
        let shares = try SplitCalculator.shares(total: 100, percentages: [33, 33, 34])
        #expect(shares.reduce(0, +) == 100)

        // A third each rounds short; the last share absorbs the drift.
        let thirds = try SplitCalculator.shares(total: 10, percentages: [Decimal(string: "33.34")!, Decimal(string: "33.33")!, Decimal(string: "33.33")!])
        #expect(thirds.reduce(0, +) == 10)
    }

    @Test func percentagesMustSumToOneHundred() {
        #expect(throws: SplitError.invalidPercentages) {
            try SplitCalculator.shares(total: 100, percentages: [50, 40])
        }
        #expect(throws: SplitError.invalidPercentages) {
            try SplitCalculator.shares(total: 100, percentages: [110, -10])
        }
    }

    // MARK: - Balances and settlement

    private func split(_ participants: [(String, Decimal, Decimal)]) -> RecordSplit {
        RecordSplit(recordID: UUID(),
                    participants: participants.map { SplitParticipant(name: $0.0, share: $0.1, paid: $0.2) })
    }

    @Test func balancesNetWhatEachPersonPaidAgainstTheirShare() {
        // Ana fronts 90 for three people at 30 each.
        let balances = SplitCalculator.balances([split([("Ana", 30, 90), ("Bo", 30, 0), ("Cy", 30, 0)])])
        #expect(balances["Ana"] == 60)
        #expect(balances["Bo"] == -30)
        #expect(balances["Cy"] == -30)
    }

    @Test func balancesCancelAcrossSeveralSplits() {
        let first = split([("Ana", 30, 60), ("Bo", 30, 0)])
        let second = split([("Ana", 30, 0), ("Bo", 30, 60)])
        // Each fronted one bill, so nobody is left owing.
        #expect(SplitCalculator.balances([first, second]).isEmpty)
    }

    @Test func settlementClearsEveryBalance() {
        let balances = ["Ana": Decimal(60), "Bo": Decimal(-30), "Cy": Decimal(-30)]
        let settlements = SplitCalculator.settlements(from: balances)

        #expect(settlements.count == 2)
        #expect(settlements.allSatisfy { $0.to == "Ana" })
        #expect(settlements.reduce(Decimal.zero) { $0 + $1.amount } == 60)

        // Applying the suggestions must leave everyone at zero.
        var remaining = balances
        for suggestion in settlements {
            remaining[suggestion.from, default: 0] += suggestion.amount
            remaining[suggestion.to, default: 0] -= suggestion.amount
        }
        #expect(remaining.values.allSatisfy { $0 == 0 })
    }

    /// Two creditors and two debtors should not need four payments.
    @Test func settlementUsesFewPaymentsForAMixedGroup() {
        let balances = ["Ana": Decimal(50), "Bo": Decimal(30), "Cy": Decimal(-60), "Di": Decimal(-20)]
        let settlements = SplitCalculator.settlements(from: balances)

        #expect(settlements.count <= 3)
        var remaining = balances
        for suggestion in settlements {
            remaining[suggestion.from, default: 0] += suggestion.amount
            remaining[suggestion.to, default: 0] -= suggestion.amount
        }
        #expect(remaining.values.allSatisfy { $0 == 0 })
    }

    @Test func aSettledGroupNeedsNoPayments() {
        #expect(SplitCalculator.settlements(from: [:]).isEmpty)
        #expect(SplitCalculator.settlements(from: ["Ana": 0, "Bo": 0]).isEmpty)
    }

    /// The same balances must always produce the same plan, or the list would reshuffle.
    @Test func settlementIsDeterministic() {
        let balances = ["Ana": Decimal(40), "Bo": Decimal(40), "Cy": Decimal(-80)]
        let first = SplitCalculator.settlements(from: balances)
        let second = SplitCalculator.settlements(from: balances)
        #expect(first == second)
    }

    // MARK: - Validation

    @Test func aSplitMustCoverTheRecordExactly() {
        let good = split([("Ana", 30, 60), ("Bo", 30, 0)])
        #expect(throws: Never.self) { try good.validate(against: 60) }

        #expect(throws: SplitError.sharesDoNotSumToTotal) { try good.validate(against: 50) }

        let unpaid = split([("Ana", 30, 0), ("Bo", 30, 0)])
        #expect(throws: SplitError.paymentsDoNotSumToTotal) { try unpaid.validate(against: 60) }

        let alone = split([("Ana", 60, 60)])
        #expect(throws: SplitError.needsTwoParticipants) { try alone.validate(against: 60) }

        let unnamed = split([("Ana", 30, 60), ("  ", 30, 0)])
        #expect(throws: SplitError.invalidName) { try unnamed.validate(against: 60) }
    }

    /// A bill fronted for a group must count toward the payer's budget only for their own share.
    @Test func onlyTheOwnersShareCountsTowardTheirBudget() {
        var value = split([("You", 30, 90), ("Bo", 30, 0), ("Cy", 30, 0)])
        value.ownerParticipantID = value.participants[0].id

        #expect(value.ownerShare == 30)
        #expect(value.total == 90)
        #expect(SplitUseCases.ownerShares([value])[value.recordID] == 30)
    }
}

@MainActor
struct SplitBudgetTests {
    /// The payer's budget should see 30, not the 90 that left their account.
    @Test func budgetsCountTheOwnerShareOfASplitRecord() {
        let account = Account(name: "Cash", type: .cash, currencyCode: "USD")
        let category = WalletCategory(name: "Food")
        var draft = RecordDraft()
        draft.kind = .expense
        draft.accountID = account.id
        draft.categoryID = category.id
        draft.amount = 90
        let now = Date()
        draft.date = now
        let record = WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")

        var budget = Budget(name: "Food", amount: 100, currencyCode: "USD", categoryID: category.id)
        budget.startDate = now.addingTimeInterval(-1)

        let whole = BudgetProgress.calculate(budget: budget, records: [record], accounts: [account],
                                             categories: [category], now: now)
        #expect(whole?.spent == 90)

        let shared = BudgetProgress.calculate(budget: budget, records: [record], accounts: [account],
                                              categories: [category], now: now,
                                              ownerShares: [record.id: 30])
        #expect(shared?.spent == 30)
    }
}

@MainActor
struct SplitStorageTests {
    @Test func splitsRoundTripAndAreReplacedRatherThanDuplicated() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = SplitUseCases(repository: repository)
        let recordID = UUID()

        let first = RecordSplit(recordID: recordID,
                                participants: [SplitParticipant(name: "You", share: 30, paid: 60),
                                               SplitParticipant(name: "Bo", share: 30, paid: 0)])
        try await useCases.save(first, recordAmount: 60)
        #expect(try await useCases.load().count == 1)

        // Saving again for the same record replaces it; a record has one split.
        let second = RecordSplit(recordID: recordID,
                                 participants: [SplitParticipant(name: "You", share: 20, paid: 60),
                                                SplitParticipant(name: "Bo", share: 20, paid: 0),
                                                SplitParticipant(name: "Cy", share: 20, paid: 0)])
        try await useCases.save(second, recordAmount: 60)

        let loaded = try await useCases.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].participants.count == 3)
    }

    /// A split must never outlive the record it divides.
    @Test func deletingARecordRemovesItsSplit() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accounts = AccountUseCases(repository: repository)
        try await accounts.create(name: "Cash", type: .cash, currencyCode: "USD")
        let account = try #require(try await accounts.load().first)
        let category = try #require(try await CategoryUseCases(repository: repository).load()
            .first { $0.parentID == nil })

        var draft = RecordDraft()
        draft.accountID = account.id
        draft.categoryID = category.id
        draft.amount = 60
        let recordID = UUID()
        try await RecordUseCases(repository: repository).create(id: recordID, draft: draft)

        try await SplitUseCases(repository: repository).save(
            RecordSplit(recordID: recordID,
                        participants: [SplitParticipant(name: "You", share: 30, paid: 60),
                                       SplitParticipant(name: "Bo", share: 30, paid: 0)]),
            recordAmount: 60)

        try await RecordUseCases(repository: repository).delete(id: recordID)
        #expect(try await SplitUseCases(repository: repository).load().isEmpty)
    }

    @Test func resettingTheWalletRemovesSplits() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        try await SplitUseCases(repository: repository).save(
            RecordSplit(recordID: UUID(),
                        participants: [SplitParticipant(name: "You", share: 5, paid: 10),
                                       SplitParticipant(name: "Bo", share: 5, paid: 0)]),
            recordAmount: 10)

        try await ResetWalletUseCase(repository: repository).execute()
        #expect(try await repository.fetchSplits().isEmpty)
    }
}
