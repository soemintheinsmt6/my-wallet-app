import Foundation
import Testing
import WalletData
import WalletDomain
@testable import WalletFeature

struct DebtCalculationTests {
    private let now = Date(timeIntervalSince1970: 1_705_320_000)

    private func debt(_ person: String, _ direction: DebtDirection, _ amount: Decimal,
                      currency: String = "USD", due: Date? = nil) -> Debt {
        Debt(person: person, direction: direction, amount: amount, currencyCode: currency, dueDate: due)
    }

    @Test func outstandingFallsAsPaymentsAreRecorded() {
        let owed = debt("Ana", .owedToMe, 100)
        let progress = DebtProgress(debt: owed, payments: [
            DebtPayment(debtID: owed.id, amount: 30),
            DebtPayment(debtID: owed.id, amount: 20),
        ])

        #expect(progress.paid == 50)
        #expect(progress.outstanding == 50)
        #expect(!progress.isSettled)
        #expect(progress.fraction == 0.5)
    }

    @Test func aFullyPaidDebtIsSettledAndNeverGoesNegative() {
        let owed = debt("Ana", .owedToMe, 100)
        let progress = DebtProgress(debt: owed, payments: [
            DebtPayment(debtID: owed.id, amount: 100),
            // A stray extra payment must not drive the balance below zero.
            DebtPayment(debtID: owed.id, amount: 25),
        ])

        #expect(progress.outstanding == 0)
        #expect(progress.isSettled)
        #expect(progress.fraction == 1)
    }

    /// Opposite directions cancel, so one number says who owes whom.
    @Test func balancesNetPerPersonAndKeepCurrenciesApart() {
        let owed = debt("Ana", .owedToMe, 100)
        let owing = debt("Ana", .iOwe, 40)
        let euro = debt("Ana", .owedToMe, 60, currency: "EUR")
        let progress = DebtUseCases.progress(debts: [owed, owing, euro], payments: [])

        let balances = DebtUseCases.balances(progress)
        let usd = try? #require(balances.first { $0.currencyCode == "USD" })
        #expect(usd?.net == 60)
        let eur = try? #require(balances.first { $0.currencyCode == "EUR" })
        #expect(eur?.net == 60)
        #expect(balances.count == 2)
    }

    @Test func aPersonWhoOwesNothingReadsAsSettled() {
        let owed = debt("Ana", .owedToMe, 50)
        let owing = debt("Ana", .iOwe, 50)
        let balances = DebtUseCases.balances(DebtUseCases.progress(debts: [owed, owing], payments: []))

        #expect(balances.count == 1)
        #expect(balances[0].net == 0)
        #expect(balances[0].isSettled)
    }

    /// Names differing only by case are the same person.
    @Test func peopleAreMatchedIgnoringCase() {
        let first = debt("Ana", .owedToMe, 30)
        let second = debt("ANA", .owedToMe, 20)
        let balances = DebtUseCases.balances(DebtUseCases.progress(debts: [first, second], payments: []))

        #expect(balances.count == 1)
        #expect(balances[0].net == 50)
    }

    @Test func settledDebtsSinkBelowOutstandingOnes() {
        let settled = debt("Ana", .owedToMe, 10)
        let open = debt("Bo", .owedToMe, 10)
        let progress = DebtUseCases.progress(
            debts: [settled, open],
            payments: [DebtPayment(debtID: settled.id, amount: 10)])

        #expect(progress.first?.debt.person == "Bo")
        #expect(progress.last?.isSettled == true)
    }

    @Test func overdueOnlyAppliesWhileStillOutstanding() {
        let past = now.addingTimeInterval(-86400)
        let open = DebtProgress(debt: debt("Ana", .owedToMe, 10, due: past), payments: [])
        #expect(open.isOverdue)

        let paid = debt("Ana", .owedToMe, 10, due: past)
        let closed = DebtProgress(debt: paid, payments: [DebtPayment(debtID: paid.id, amount: 10)])
        #expect(!closed.isOverdue)
    }

    @Test func validationRejectsBlankNamesAndBadAmounts() {
        var value = debt("  ", .owedToMe, 10)
        #expect(throws: DebtError.invalidPerson) { try value.validate() }

        value = debt("Ana", .owedToMe, 0)
        #expect(throws: (any Error).self) { try value.validate() }

        value = debt("Ana", .owedToMe, 10, currency: "ZZZ")
        #expect(throws: DebtError.invalidCurrency) { try value.validate() }
    }

    /// Settling a debt someone owes brings money in; one the user owes sends it out.
    @Test func settlementDirectionMatchesWhoOwesWhom() {
        #expect(DebtDirection.owedToMe.settlementKind == .income)
        #expect(DebtDirection.iOwe.settlementKind == .expense)
    }
}

struct GoalCalculationTests {
    private let now = Date(timeIntervalSince1970: 1_705_320_000)

    private func goal(target: Decimal = 1000, deadline: Date? = nil) -> SavingsGoal {
        SavingsGoal(name: "Laptop", targetAmount: target, deadline: deadline)
    }

    @Test func progressTracksContributionsAndWithdrawals() {
        let target = goal()
        let progress = GoalProgress(goal: target, contributions: [
            GoalContribution(goalID: target.id, amount: 300, date: now.addingTimeInterval(-20 * 86400)),
            GoalContribution(goalID: target.id, amount: 300, date: now.addingTimeInterval(-10 * 86400)),
            GoalContribution(goalID: target.id, amount: -100, date: now),
        ])

        #expect(progress.saved == 500)
        #expect(progress.remaining == 500)
        #expect(progress.fraction == 0.5)
        #expect(!progress.isAchieved)
    }

    @Test func reachingTheTargetMarksTheGoalAchieved() {
        let target = goal(target: 100)
        let progress = GoalProgress(goal: target,
                                    contributions: [GoalContribution(goalID: target.id, amount: 120)])
        #expect(progress.isAchieved)
        #expect(progress.remaining == 0)
        #expect(progress.fraction == 1)
    }

    /// 500 saved over 10 days is 50 a day, so the remaining 500 takes another 10.
    @Test func completionIsProjectedFromTheSavingRate() {
        let target = goal()
        let progress = GoalProgress(goal: target, contributions: [
            GoalContribution(goalID: target.id, amount: 500, date: now.addingTimeInterval(-10 * 86400)),
        ])

        let projected = try? #require(progress.projectedCompletion(now: now))
        let days = (projected?.timeIntervalSince(now) ?? 0) / 86400
        #expect(days >= 9 && days <= 11)
    }

    @Test func thereIsNoProjectionWithoutContributionsOrOnceAchieved() {
        let empty = GoalProgress(goal: goal(), contributions: [])
        #expect(empty.projectedCompletion(now: now) == nil)
        #expect(empty.dailyRate(now: now) == nil)

        let target = goal(target: 100)
        let done = GoalProgress(goal: target,
                                contributions: [GoalContribution(goalID: target.id, amount: 100)])
        #expect(done.projectedCompletion(now: now) == nil)
    }

    @Test func beingBehindScheduleComparesTheProjectionToTheDeadline() {
        let soon = now.addingTimeInterval(2 * 86400)
        let far = now.addingTimeInterval(400 * 86400)
        let contribution = { (target: SavingsGoal) in
            [GoalContribution(goalID: target.id, amount: 500, date: now.addingTimeInterval(-10 * 86400))]
        }

        let tight = goal(deadline: soon)
        #expect(GoalProgress(goal: tight, contributions: contribution(tight)).isBehindSchedule(now: now))

        let relaxed = goal(deadline: far)
        #expect(!GoalProgress(goal: relaxed, contributions: contribution(relaxed)).isBehindSchedule(now: now))
    }

    /// An achieved goal is never behind, whatever its deadline said.
    @Test func anAchievedGoalIsNeverBehindSchedule() {
        let target = goal(target: 100, deadline: now.addingTimeInterval(-86400))
        let progress = GoalProgress(goal: target,
                                    contributions: [GoalContribution(goalID: target.id, amount: 100)])
        #expect(!progress.isBehindSchedule(now: now))
    }

    @Test func achievedGoalsSinkBelowUnfinishedOnes() {
        let done = SavingsGoal(name: "Done", targetAmount: 10)
        let open = SavingsGoal(name: "Open", targetAmount: 10)
        let ordered = GoalUseCases.progress(
            goals: [done, open],
            contributions: [GoalContribution(goalID: done.id, amount: 10)])

        #expect(ordered.first?.goal.name == "Open")
        #expect(ordered.last?.isAchieved == true)
    }
}

@MainActor
struct DebtGoalStorageTests {
    private func repository() async throws -> SwiftDataWalletRepository {
        try await SwiftDataWalletRepository.make(configuration: .inMemory)
    }

    @Test func debtsAndPaymentsRoundTrip() async throws {
        let repository = try await repository()
        let useCases = DebtUseCases(repository: repository)
        var debt = Debt(person: "Ana", direction: .iOwe, amount: 200, currencyCode: "USD")
        debt.note = "Concert tickets"
        try await useCases.save(debt)

        var loaded = try await useCases.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].debt.person == "Ana")
        #expect(loaded[0].debt.note == "Concert tickets")

        try await useCases.pay(loaded[0], amount: 50)
        loaded = try await useCases.load()
        #expect(loaded[0].outstanding == 150)
    }

    @Test func aPaymentBeyondTheOutstandingBalanceIsRefused() async throws {
        let repository = try await repository()
        let useCases = DebtUseCases(repository: repository)
        try await useCases.save(Debt(person: "Ana", direction: .owedToMe, amount: 100))
        let progress = try #require(try await useCases.load().first)

        await #expect(throws: DebtError.paymentExceedsOutstanding) {
            try await useCases.pay(progress, amount: 101)
        }
        await #expect(throws: DebtError.invalidPaymentAmount) {
            try await useCases.pay(progress, amount: 0)
        }
        #expect(try await useCases.load().first?.paid == 0)
    }

    /// A payment without its debt could never be shown, so it must not survive.
    @Test func deletingADebtRemovesItsPayments() async throws {
        let repository = try await repository()
        let useCases = DebtUseCases(repository: repository)
        try await useCases.save(Debt(person: "Ana", direction: .owedToMe, amount: 100))
        let progress = try #require(try await useCases.load().first)
        try await useCases.pay(progress, amount: 40)

        try await useCases.delete(id: progress.debt.id)

        #expect(try await useCases.load().isEmpty)
        #expect(try await repository.fetchDebtPayments().isEmpty)
    }

    @Test func goalsAndContributionsRoundTripAndCascade() async throws {
        let repository = try await repository()
        let useCases = GoalUseCases(repository: repository)
        try await useCases.save(SavingsGoal(name: "Laptop", targetAmount: 1000))
        let goal = try #require(try await useCases.load().first).goal

        try await useCases.contribute(to: goal, amount: 250)
        #expect(try await useCases.load().first?.saved == 250)

        try await useCases.delete(id: goal.id)
        #expect(try await useCases.load().isEmpty)
        #expect(try await repository.fetchGoalContributions().isEmpty)
    }

    @Test func aZeroContributionIsRefused() async throws {
        let repository = try await repository()
        let useCases = GoalUseCases(repository: repository)
        try await useCases.save(SavingsGoal(name: "Laptop", targetAmount: 100))
        let goal = try #require(try await useCases.load().first).goal

        await #expect(throws: GoalError.invalidContribution) {
            try await useCases.contribute(to: goal, amount: 0)
        }
    }

    @Test func resettingTheWalletRemovesDebtsAndGoals() async throws {
        let repository = try await repository()
        try await DebtUseCases(repository: repository).save(Debt(person: "Ana", direction: .iOwe, amount: 10))
        try await GoalUseCases(repository: repository).save(SavingsGoal(name: "Laptop", targetAmount: 10))

        try await ResetWalletUseCase(repository: repository).execute()

        #expect(try await repository.fetchDebts().isEmpty)
        #expect(try await repository.fetchGoals().isEmpty)
    }
}

/// Money that changes hands when a debt is made is recorded as balance adjustments, so a loan moves
/// the balance out and back without ever counting as income or spending.
@MainActor
struct DebtMoneyMovedTests {
    private func setup() async throws -> (SwiftDataWalletRepository, DebtsViewModel, RecordsViewModel, Account) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let account = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 1000))
        try await repository.createAccount(account)
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository),
                                       accounts: AccountUseCases(repository: repository),
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        await records.reload()
        return (repository, DebtsViewModel(repository: repository, records: records), records, account)
    }

    private func balance(_ repository: SwiftDataWalletRepository) async throws -> Decimal? {
        try await repository.fetchAccounts().first?.settings.currentBalance
    }

    @Test func lendingAndBeingRepaidReturnsTheBalanceWithoutCountingAsIncomeOrSpending() async throws {
        let (repository, viewModel, records, account) = try await setup()
        try await viewModel.save(Debt(person: "Ana", direction: .owedToMe, amount: 300), moneyMovedThrough: account)

        #expect(try await balance(repository) == 700)
        let progress = try #require(viewModel.debts.first)
        let opening = try #require(records.records.first)
        #expect(progress.debt.openingRecordID == opening.id)
        #expect(opening.draft.isAdjustment && opening.draft.kind == .expense && opening.draft.amount == 300)

        try await viewModel.pay(progress, amount: 300, account: account, categoryID: nil)
        #expect(try await balance(repository) == 1000)
        #expect(records.records.count == 2)
        #expect(records.records.allSatisfy { $0.draft.isAdjustment && !$0.draft.countsAsActivity })
        #expect(viewModel.debts.first?.isSettled == true)
    }

    @Test func borrowingPutsMoneyInAndEditingKeepsTheAdjustmentInStep() async throws {
        let (repository, viewModel, records, account) = try await setup()
        try await viewModel.save(Debt(person: "Ben", direction: .iOwe, amount: 200), moneyMovedThrough: account)
        #expect(try await balance(repository) == 1200)

        var edited = try #require(viewModel.debts.first).debt
        edited.amount = 150
        try await viewModel.save(edited)
        #expect(try await balance(repository) == 1150)
        #expect(records.records.count == 1)
        #expect(records.records.first?.draft.amount == 150)
    }

    @Test func aDebtWithoutMovedMoneyStillSettlesAsIncomeOrAnExpense() async throws {
        let (repository, viewModel, records, account) = try await setup()
        try await viewModel.save(Debt(person: "Cy", direction: .owedToMe, amount: 50))
        #expect(try await balance(repository) == 1000)
        #expect(records.records.isEmpty)

        // Income needs a category, so the sheet asks for one for these debts.
        let progress = try #require(viewModel.debts.first)
        let category = try #require(records.categories.first)
        try await viewModel.pay(progress, amount: 50, account: account, categoryID: category.id)
        let record = try #require(records.records.first)
        #expect(!record.draft.isAdjustment && record.draft.kind == .income)
        #expect(try await balance(repository) == 1050)
    }

    @Test func aDebtThatFailsToSaveLeavesNoAdjustmentBehind() async throws {
        let (repository, viewModel, records, account) = try await setup()
        await #expect(throws: DebtError.invalidPerson) {
            try await viewModel.save(Debt(person: "  ", direction: .owedToMe, amount: 300), moneyMovedThrough: account)
        }
        #expect(records.records.isEmpty)
        #expect(try await balance(repository) == 1000)
        #expect(viewModel.debts.isEmpty)
    }
}
