import Combine
import Foundation
import WalletDomain

@MainActor
public final class PlanningViewModel: ObservableObject {
    @Published public private(set) var budgets: [Budget] = []
    @Published public private(set) var series: [RecurringSeries] = []
    @Published public private(set) var occurrences: [ScheduledOccurrence] = []
    @Published public private(set) var bills: [BillReminder] = []
    /// Split records mapped to the owner's own share, so budgets count only their part.
    @Published public var ownerShares: [UUID: Decimal] = [:]
    @Published public private(set) var isSaving = false
    @Published public private(set) var isLoading = false
    @Published public var errorMessage: String?
    /// Whether system notifications are already allowed, so the request button can be hidden.
    /// Starts true so the button does not flash before the first check in the usual case.
    @Published public private(set) var notificationsAuthorized = true
    public let records: RecordsViewModel
    private let repository: any BudgetRepository & RecurringRepository & BillReminderRepository
    private let notifications: (any WalletNotificationClient)?
    private var generation = 0
    private var isGenerating = false

    public init(repository: any BudgetRepository & RecurringRepository & BillReminderRepository,
                records: RecordsViewModel, notifications: (any WalletNotificationClient)? = nil) {
        self.repository = repository
        self.records = records
        self.notifications = notifications
    }

    public func observe() async {
        let changes = repository.changes()
        await refresh(generate: true)
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await refresh()
        }
    }

    public func refresh(generate: Bool = false) async {
        if generate { await generateDue() }
        generation += 1
        let version = generation
        isLoading = true
        defer { if version == generation { isLoading = false } }
        do {
            let budgets = try await repository.fetchBudgets()
            let series = try await repository.fetchRecurringSeries()
            let occurrences = try await repository.fetchOccurrences()
            let bills = try await repository.fetchBillReminders()
            await records.reload()
            guard version == generation else { return }
            self.budgets = budgets; self.series = series; self.occurrences = occurrences; self.bills = bills
            try await synchronizeNotifications()
        } catch is CancellationError {
        } catch { if version == generation { errorMessage = error.localizedDescription } }
    }

    /// Generates due records now, for the Recurring screen's button, then reloads. Returns how many
    /// records were added, so the button can say so; nil if generating failed (the error is
    /// reported) or a catch-up was already running and this tap added nothing of its own.
    public func generateDueRecordsNow() async -> Int? {
        let count = await generateDue()
        await refresh()
        return count
    }

    @discardableResult
    private func generateDue() async -> Int? {
        guard !isGenerating else { return nil }
        isGenerating = true
        defer { isGenerating = false }
        do { return try await repository.generateDueRecords(through: Date()) } catch {
            errorMessage = "Recurring records: \(error.localizedDescription)"
            return nil
        }
    }

    public func progress(on date: Date = Date(), categoryID: UUID? = nil) -> [BudgetProgress] {
        budgets.filter { categoryID == nil || $0.categoryID == categoryID }.compactMap {
            BudgetProgress.calculate(budget: $0, records: records.records, accounts: records.accounts,
                                     categories: records.categories, now: date, ownerShares: ownerShares)
        }
    }

    /// Each account's balance over the coming days, moved by its recurring records and unpaid bills.
    /// Accounts with something planned come first when they are forecast to fall below their
    /// threshold, soonest first.
    public func forecast(days: Int = CashFlowForecaster.defaultDays, now: Date = Date()) -> [AccountForecast] {
        let forecasts = CashFlowForecaster.forecast(accounts: records.accounts, series: series, occurrences: occurrences,
                                                    bills: bills, categories: records.categories, now: now, days: days)
        let warned = forecasts.filter { $0.firstBelowThreshold != nil }
            .sorted { ($0.firstBelowThreshold?.date ?? now) < ($1.firstBelowThreshold?.date ?? now) }
        return warned + forecasts.filter { $0.firstBelowThreshold == nil }
    }

    public func save(_ budget: Budget) async throws {
        try await mutate { try await BudgetUseCases(repository: repository).save(budget) }
    }
    public func deleteBudget(id: UUID) async throws { try await mutate { try await repository.deleteBudget(id: id) } }
    public func save(_ bill: BillReminder) async throws {
        try bill.validate()
        try await mutate { try await repository.saveBillReminder(bill) }
    }
    public func deleteBill(id: UUID) async throws { try await mutate { try await repository.deleteBillReminder(id: id) } }
    /// Settles the bill's current occurrence and records it as an expense dated `paidAt`.
    /// An account or category chosen while paying is kept on the bill for next time.
    public func pay(_ bill: BillReminder, paidAt: Date) async throws {
        guard bill.accountID != nil, bill.categoryID != nil else { throw PlanningError.missingItem }
        try await mutate {
            if let stored = bills.first(where: { $0.id == bill.id }),
               stored.accountID != bill.accountID || stored.categoryID != bill.categoryID {
                try await repository.saveBillReminder(bill)
            }
            try await repository.markBillPaid(id: bill.id, occurrenceIndex: bill.nextIndex, createRecord: true, paidAt: paidAt)
        }
    }
    public func save(_ series: RecurringSeries) async throws { try await mutate { try await repository.updateRecurringSeries(series) } }
    public func save(_ occurrence: ScheduledOccurrence) async throws { try await mutate { try await repository.saveOccurrence(occurrence) } }

    private func mutate(_ operation: () async throws -> Void) async throws {
        guard !isSaving else { throw PlanningError.busy }
        isSaving = true
        defer { isSaving = false }
        try await operation()
        await refresh()
    }

    public func requestNotifications() async {
        do {
            guard let notifications, try await notifications.requestAuthorization() else {
                notificationsAuthorized = false
                errorMessage = "Notifications are disabled. Enable them for My Wallet in system settings."
                return
            }
            notificationsAuthorized = true
            try await synchronizeNotifications()
        } catch { errorMessage = error.localizedDescription }
    }

    public func refreshNotificationAuthorization() async {
        guard let notifications else { return }
        notificationsAuthorized = await notifications.isAuthorized()
    }

    private func synchronizeNotifications() async throws {
        guard let notifications else { return }
        let now = Date()
        var notices: [WalletNotification] = []
        for bill in bills where bill.notificationsEnabled {
            guard let due = bill.nextDueDate else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = bill.recurrence.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
            let alertDate = calendar.date(byAdding: .day, value: -bill.reminderDaysBefore, to: due) ?? due
            notices.append(WalletNotification(id: "wallet.bill.\(bill.id).\(bill.nextIndex)", title: "Bill due: \(bill.name)",
                                               body: "\(bill.amount.formatted(.currency(code: bill.currencyCode))) · \(due.formatted(date: .abbreviated, time: .shortened))",
                                               date: alertDate > now ? alertDate : nil))
        }
        for value in progress() where value.budget.notificationsEnabled && value.ratio >= 0.8 {
            let level = value.ratio >= 1 ? "exceeded" : "approaching"
            notices.append(WalletNotification(id: "wallet.budget.\(value.id).\(Int(value.interval.start.timeIntervalSince1970)).\(level)",
                                               title: "\(value.budget.name): \(value.status)",
                                               body: "Spent \(value.spent.formatted(.currency(code: value.budget.currencyCode))) of \(value.limit.formatted(.currency(code: value.budget.currencyCode)))."))
        }
        try await notifications.synchronize(notices, managing: type(of: notifications).planningPrefixes)
    }
}
