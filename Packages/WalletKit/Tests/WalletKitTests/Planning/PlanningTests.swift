import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

@MainActor
struct PlanningTests {
    private let start = Date(timeIntervalSince1970: 1_706_659_200) // 2024-01-31 UTC
    private func setup() async throws -> (SwiftDataWalletRepository, Account, WalletCategory) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let account = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        try await repository.createAccount(account)
        let category = try #require(try await repository.fetchCategories().first)
        return (repository, account, category)
    }
    private func draft(account: Account, category: WalletCategory, count: Int = 4) -> RecordDraft {
        var draft = RecordDraft()
        draft.accountID = account.id; draft.categoryID = category.id; draft.amount = 10; draft.date = start
        draft.recurrence = RecurrenceRule(frequency: .monthly, count: count, timeZoneIdentifier: "UTC")
        return draft
    }

    @Test func anchoredMonthlyAndYearlySchedulesPreserveMonthEndAndStopAtLimits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let rule = RecurrenceRule(frequency: .monthly, count: 3, timeZoneIdentifier: "UTC")
        let february = try #require(rule.date(start: start, index: 1))
        let march = try #require(rule.date(start: start, index: 2))
        #expect(calendar.component(.day, from: february) == 29)
        #expect(calendar.component(.day, from: march) == 31)
        #expect(rule.date(start: start, index: 3) == nil)
        let yearly = RecurrenceRule(frequency: .yearly, timeZoneIdentifier: "UTC")
        #expect(calendar.component(.day, from: try #require(yearly.date(start: february, index: 4))) == 29)
        let ending = RecurrenceRule(frequency: .monthly, endDate: february, timeZoneIdentifier: "UTC")
        #expect(ending.date(start: start, index: 1) == february)
        #expect(ending.date(start: start, index: 2) == nil)
        #expect(throws: PlanningError.self) { try RecurrenceRule(count: 0).validate(start: start) }
    }

    @Test func dailyScheduleKeepsLocalTimeAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let anchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 9)))
        let next = try #require(RecurrenceRule(frequency: .daily, timeZoneIdentifier: "America/New_York").date(start: anchor, index: 1))
        #expect(calendar.component(.hour, from: next) == 9)
        #expect(next.timeIntervalSince(anchor) == 23 * 3600)
    }

    @Test func catchUpIsIdempotentAndDeletedGeneratedRecordsDoNotReturn() async throws {
        let (repository, account, category) = try await setup()
        let id = UUID()
        let values = draft(account: account, category: category)
        try await repository.createRecord(id: id, draft: values)
        try await repository.createRecord(id: id, draft: values)
        #expect(try await repository.fetchRecurringSeries().count == 1)
        let end = try #require(values.recurrence?.date(start: start, index: 3))
        #expect(try await repository.generateDueRecords(through: end) == 3)
        #expect(try await repository.generateDueRecords(through: end) == 0)
        #expect(try await repository.fetchRecords().count == 4)
        #expect(try await repository.fetchAccounts().first?.settings.currentBalance == 60)
        let generatedID = ScheduledOccurrence.identifier(owner: id, index: 1, kind: "recurring")
        try await repository.deleteRecord(id: generatedID)
        #expect(try await repository.generateDueRecords(through: end) == 0)
        #expect(try await repository.fetchRecords().count == 3)
        #expect(try await repository.fetchAccounts().first?.settings.currentBalance == 70)
    }

    @Test func pauseResumeSkipAndModifiedOccurrencesApplyExactlyOnce() async throws {
        let (repository, account, category) = try await setup()
        let id = UUID()
        try await repository.createRecord(id: id, draft: draft(account: account, category: category))
        var series = try #require(try await repository.fetchRecurringSeries().first)
        series.state = .paused
        try await repository.updateRecurringSeries(series)
        let end = try #require(series.rule.date(start: start, index: 3))
        #expect(try await repository.generateDueRecords(through: end) == 0)
        try await repository.saveOccurrence(ScheduledOccurrence(seriesID: id, index: 1, skipped: true))
        var modified = series.template
        modified.amount = 25
        modified.date = try #require(series.rule.date(start: start, index: 2))
        modified.note = "One occurrence only"
        try await repository.saveOccurrence(ScheduledOccurrence(seriesID: id, index: 2, overrideDraft: modified))
        series.state = .active
        try await repository.updateRecurringSeries(series)
        #expect(try await repository.generateDueRecords(through: end) == 2)
        #expect(try await repository.fetchAccounts().first?.settings.currentBalance == 55)
        #expect(try await repository.fetchRecords().filter { $0.draft.note == "One occurrence only" }.count == 1)
        await #expect(throws: PlanningError.self) { try await repository.saveOccurrence(ScheduledOccurrence(seriesID: id, index: 2, skipped: true)) }
        series.state = .cancelled
        series.nextIndex = 0
        try await repository.updateRecurringSeries(series)
        #expect(try await repository.fetchRecurringSeries().first?.nextIndex == 4)
        #expect(try await repository.generateDueRecords(through: .distantFuture) == 0)
    }

    @Test func movedOccurrenceWaitsForItsNewDateAndFailedCatchUpPreservesCursor() async throws {
        let (repository, account, category) = try await setup()
        let id = UUID()
        try await repository.createRecord(id: id, draft: draft(account: account, category: category, count: 2))
        let series = try #require(try await repository.fetchRecurringSeries().first)
        let originalDate = try #require(series.nextDate)
        var modified = series.template
        modified.date = originalDate.addingTimeInterval(86400)
        try await repository.saveOccurrence(ScheduledOccurrence(seriesID: id, index: 1, overrideDraft: modified))
        #expect(try await repository.generateDueRecords(through: originalDate) == 0)
        modified.accountID = UUID()
        try await repository.saveOccurrence(ScheduledOccurrence(seriesID: id, index: 1, overrideDraft: modified))
        await #expect(throws: RecordValidationError.self) { try await repository.generateDueRecords(through: modified.date) }
        #expect(try await repository.fetchRecurringSeries().first?.nextIndex == 2)
        #expect(try await repository.fetchRecords().count == 1)
        #expect(try await repository.fetchOccurrences().first?.completed == false)
    }

    @Test func postponedOccurrenceDoesNotBlockLaterRegularRecords() async throws {
        let (repository, account, category) = try await setup()
        let id = UUID()
        try await repository.createRecord(id: id, draft: draft(account: account, category: category, count: 3))
        let series = try #require(try await repository.fetchRecurringSeries().first)
        let march = try #require(series.rule.date(start: start, index: 2))
        var modified = series.template
        modified.date = march.addingTimeInterval(86400 * 10)
        modified.amount = 15
        try await repository.saveOccurrence(ScheduledOccurrence(seriesID: id, index: 1, overrideDraft: modified))
        #expect(try await repository.generateDueRecords(through: march) == 1)
        #expect(try await repository.fetchAccounts().first?.settings.currentBalance == 80)
        #expect(try await repository.generateDueRecords(through: modified.date) == 1)
        #expect(try await repository.fetchAccounts().first?.settings.currentBalance == 65)
        #expect(try await repository.generateDueRecords(through: modified.date) == 0)
    }

    @Test func billPaymentAtomicallyCreatesAnExpenseAndRepeatedConfirmationIsSafe() async throws {
        let (repository, account, category) = try await setup()
        let bill = BillReminder(name: "Rent", amount: 25, dueDate: start,
                                recurrence: RecurrenceRule(frequency: .monthly, count: 2, timeZoneIdentifier: "UTC"),
                                accountID: account.id, categoryID: category.id)
        try await repository.saveBillReminder(bill)
        try await repository.markBillPaid(id: bill.id, occurrenceIndex: 0, createRecord: true, paidAt: start)
        try await repository.markBillPaid(id: bill.id, occurrenceIndex: 0, createRecord: true, paidAt: start)
        #expect(try await repository.fetchRecords().count == 1)
        #expect(try await repository.fetchAccounts().first?.settings.currentBalance == 75)
        let next = try #require(try await repository.fetchBillReminders().first)
        #expect(next.nextIndex == 1)
        #expect(next.nextDueDate == bill.recurrence?.date(start: start, index: 1))
        try await repository.markBillPaid(id: bill.id, occurrenceIndex: 1, createRecord: false, paidAt: start)
        #expect(try await repository.fetchBillReminders().first?.isPaid == true)
        #expect(try await repository.fetchRecords().count == 1)
    }

    @Test func invalidBillPaymentDoesNotAdvanceOrChangeBalancesAndDeleteKeepsPayments() async throws {
        let (repository, _, _) = try await setup()
        let bill = BillReminder(name: "Unlinked", amount: 20, dueDate: start)
        try await repository.saveBillReminder(bill)
        await #expect(throws: RecordValidationError.self) { try await repository.markBillPaid(id: bill.id, occurrenceIndex: 0, createRecord: true, paidAt: start) }
        #expect(try await repository.fetchBillReminders().first?.nextIndex == 0)
        #expect(try await repository.fetchRecords().isEmpty)
        try await repository.markBillPaid(id: bill.id, occurrenceIndex: 0, createRecord: false, paidAt: start)
        try await repository.deleteBillReminder(id: bill.id)
        #expect(try await repository.fetchBillReminders().isEmpty)
    }

    @Test func budgetsRollOverOnlyUnusedAmountsAndRespectCategoriesCurrencyAndExclusion() async throws {
        let (repository, account, category) = try await setup()
        var values = draft(account: account, category: category)
        values.recurrence = nil
        values.amount = 40
        try await repository.createRecord(id: UUID(), draft: values)
        let budget = Budget(name: "Food", amount: 100, categoryID: category.id, startDate: start, rollover: true, timeZoneIdentifier: "UTC")
        try await BudgetUseCases(repository: repository).save(budget)
        let secondStart = try #require(budget.interval(index: 1)?.start)
        values.date = secondStart
        values.amount = 30
        try await repository.createRecord(id: UUID(), draft: values)
        let records = try await repository.fetchRecords()
        let accounts = try await repository.fetchAccounts()
        let categories = try await repository.fetchCategories()
        let progress = try #require(BudgetProgress.calculate(budget: budget, records: records, accounts: accounts, categories: categories, now: secondStart))
        #expect(progress.carried == 60)
        #expect(progress.spent == 30)
        #expect(progress.limit == 160)
        #expect(progress.remaining == 130)
        var excludedSettings = account.settings
        excludedSettings.excludeFromStats = true
        let excluded = Account(id: account.id, name: account.name, type: account.type, settings: excludedSettings)
        #expect(BudgetProgress.calculate(budget: budget, records: records, accounts: [excluded], categories: categories, now: secondStart)?.spent == 0)
        var foreign = budget
        foreign.currencyCode = "EUR"
        #expect(BudgetProgress.calculate(budget: foreign, records: records, accounts: accounts, categories: categories, now: secondStart)?.spent == 0)
        var otherCategory = budget
        otherCategory.categoryID = UUID()
        #expect(BudgetProgress.calculate(budget: otherCategory, records: records, accounts: accounts, categories: categories, now: secondStart)?.spent == 0)
    }

    @Test func budgetValidationAndCustomPeriodsDoNotCreateInvalidPlans() async throws {
        let (repository, _, _) = try await setup()
        var budget = Budget(name: "Custom", amount: 10, period: .custom, startDate: start, endDate: start)
        await #expect(throws: PlanningError.self) { try await BudgetUseCases(repository: repository).save(budget) }
        #expect(try await repository.fetchBudgets().isEmpty)
        budget.endDate = start.addingTimeInterval(86400)
        try await repository.saveBudget(budget)
        #expect(BudgetProgress.calculate(budget: budget, records: [], accounts: [], categories: [], now: budget.endDate) == nil)
        try await repository.deleteBudget(id: budget.id)
        #expect(try await repository.fetchBudgets().isEmpty)
    }

    @Test func planningPublishesSavesAndSynchronizesBudgetAndBillNotices() async throws {
        let (repository, account, category) = try await setup()
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: AccountUseCases(repository: repository),
                                       categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let notifications = TestNotifications()
        let viewModel = PlanningViewModel(repository: repository, records: records, notifications: notifications)
        let today = Calendar.current.startOfDay(for: Date())
        var values = draft(account: account, category: category)
        values.recurrence = nil; values.date = today; values.amount = 85
        try await repository.createRecord(id: UUID(), draft: values)
        let budget = Budget(name: "Limit", amount: 100, startDate: today, notificationsEnabled: true)
        try await viewModel.save(budget)
        #expect(viewModel.budgets.count == 1)
        #expect(notifications.notices.contains { $0.id.contains("approaching") })
        let bill = BillReminder(name: "Utility", amount: 5, dueDate: Date().addingTimeInterval(86400 * 3), notificationsEnabled: true)
        try await viewModel.save(bill)
        #expect(notifications.notices.contains { $0.id.contains(bill.id.uuidString) && $0.date != nil })
        try await viewModel.deleteBill(id: bill.id)
        #expect(!notifications.notices.contains { $0.id.contains(bill.id.uuidString) })
        #expect(!viewModel.isSaving)
        notifications.authorized = false
        await viewModel.requestNotifications()
        #expect(viewModel.errorMessage?.contains("disabled") == true)
        var invalid = budget
        invalid.name = ""
        await #expect(throws: PlanningError.self) { try await viewModel.save(invalid) }
        #expect(viewModel.budgets.first?.name == "Limit")
        #expect(!viewModel.isSaving)
    }

    @Test func resetRemovesAllPlansAndOccurrenceReceipts() async throws {
        let (repository, account, category) = try await setup()
        try await repository.createRecord(id: UUID(), draft: draft(account: account, category: category))
        _ = try await repository.generateDueRecords(through: start.addingTimeInterval(86400 * 100))
        try await repository.saveBudget(Budget(amount: 50))
        try await repository.saveBillReminder(BillReminder(name: "Bill", amount: 5))
        try await repository.resetWalletData()
        #expect(try await repository.fetchRecurringSeries().isEmpty)
        #expect(try await repository.fetchOccurrences().isEmpty)
        #expect(try await repository.fetchBudgets().isEmpty)
        #expect(try await repository.fetchBillReminders().isEmpty)
    }
}

@MainActor
private final class TestNotifications: WalletNotificationClient {
    var notices: [WalletNotification] = []
    var managedPrefixes: [String] = []
    var authorized = true
    func requestAuthorization() async throws -> Bool { authorized }
    func synchronize(_ notifications: [WalletNotification], managing prefixes: [String]) async throws {
        notices = notifications
        managedPrefixes = prefixes
    }
}
