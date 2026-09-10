import Combine
import CoreData
import Foundation
import SwiftData
import WalletDomain

@MainActor
public final class SwiftDataWalletRepository: WalletRepository, AccountRepository, CategoryRepository, TagRepository, RecordRepository, WalletResetRepository, BudgetRepository, RecurringRepository, BillReminderRepository, ReceiptRepository, DebtRepository, GoalRepository {
    private let store: WalletStore
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    private init(store: WalletStore) {
        self.store = store
        // SwiftData's CloudKit backing store posts notifications after remote imports.
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .sink { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyChanges() }
            }
            .store(in: &subscriptions)
    }

    public static func make(configuration: WalletStorageConfiguration) async throws -> SwiftDataWalletRepository {
        let store = try await Task.detached {
            let container = try WalletPersistence.makeContainer(configuration: configuration)
            return WalletStore(modelContainer: container)
        }.value
        return SwiftDataWalletRepository(store: store)
    }

    public func fetchEntries() async throws -> [WalletEntry] { try await store.fetchEntries() }

    public func resetWalletData() async throws {
        try await store.resetWalletData()
        notifyChanges()
    }

    public func fetchBudgets() async throws -> [Budget] { try await store.fetchBudgets() }
    public func fetchRecurringSeries() async throws -> [RecurringSeries] { try await store.fetchRecurringSeries() }
    public func fetchOccurrences() async throws -> [ScheduledOccurrence] { try await store.fetchOccurrences() }
    public func fetchBillReminders() async throws -> [BillReminder] { try await store.fetchBillReminders() }

    public func saveBudget(_ budget: Budget) async throws {
        try await store.saveBudget(budget)
        notifyChanges()
    }

    public func deleteBudget(id: UUID) async throws {
        try await store.deleteBudget(id: id)
        notifyChanges()
    }

    public func updateRecurringSeries(_ series: RecurringSeries) async throws {
        try await store.updateRecurringSeries(series)
        notifyChanges()
    }

    public func saveOccurrence(_ occurrence: ScheduledOccurrence) async throws {
        try await store.saveOccurrence(occurrence)
        notifyChanges()
    }

    public func saveBillReminder(_ bill: BillReminder) async throws {
        try await store.saveBillReminder(bill)
        notifyChanges()
    }

    public func deleteBillReminder(id: UUID) async throws {
        try await store.deleteBillReminder(id: id)
        notifyChanges()
    }

    public func markBillPaid(id: UUID, occurrenceIndex: Int, createRecord: Bool, paidAt: Date) async throws {
        try await store.markBillPaid(id: id, occurrenceIndex: occurrenceIndex, createRecord: createRecord, paidAt: paidAt)
        notifyChanges()
    }

    public func generateDueRecords(through date: Date) async throws -> Int {
        let count = try await store.generateDueRecords(through: date)
        if count > 0 { notifyChanges() }
        return count
    }

    public func fetchAccounts() async throws -> [Account] { try await store.fetchAccounts() }

    public func fetchRecords() async throws -> [WalletRecord] { try await store.fetchRecords() }

    public func recordPhoto(id: UUID) async throws -> Data? { try await store.recordPhoto(id: id) }

    public func createRecord(id: UUID, draft: RecordDraft) async throws {
        try await store.createRecord(id: id, draft: draft)
        notifyChanges()
    }

    public func updateRecord(id: UUID, draft: RecordDraft) async throws {
        try await store.updateRecord(id: id, draft: draft)
        notifyChanges()
    }

    public func fetchDebts() async throws -> [Debt] { try await store.fetchDebts() }
    public func fetchDebtPayments() async throws -> [DebtPayment] { try await store.fetchDebtPayments() }

    public func saveDebt(_ debt: Debt) async throws {
        try await store.saveDebt(debt)
        notifyChanges()
    }

    public func deleteDebt(id: UUID) async throws {
        try await store.deleteDebt(id: id)
        notifyChanges()
    }

    public func saveDebtPayment(_ payment: DebtPayment) async throws {
        try await store.saveDebtPayment(payment)
        notifyChanges()
    }

    public func deleteDebtPayment(id: UUID) async throws {
        try await store.deleteDebtPayment(id: id)
        notifyChanges()
    }

    public func fetchGoals() async throws -> [SavingsGoal] { try await store.fetchGoals() }
    public func fetchGoalContributions() async throws -> [GoalContribution] {
        try await store.fetchGoalContributions()
    }

    public func saveGoal(_ goal: SavingsGoal) async throws {
        try await store.saveGoal(goal)
        notifyChanges()
    }

    public func deleteGoal(id: UUID) async throws {
        try await store.deleteGoal(id: id)
        notifyChanges()
    }

    public func saveGoalContribution(_ contribution: GoalContribution) async throws {
        try await store.saveGoalContribution(contribution)
        notifyChanges()
    }

    public func deleteGoalContribution(id: UUID) async throws {
        try await store.deleteGoalContribution(id: id)
        notifyChanges()
    }

    public func fetchReceipts(recordID: UUID) async throws -> [Receipt] {
        try await store.fetchReceipts(recordID: recordID)
    }

    public func receiptPageCounts() async throws -> [UUID: Int] { try await store.receiptPageCounts() }

    public func saveReceipts(_ receipts: [Receipt]) async throws {
        try await store.saveReceipts(receipts)
        notifyChanges()
    }

    public func deleteReceipt(id: UUID) async throws {
        try await store.deleteReceipt(id: id)
        notifyChanges()
    }

    public func deleteReceipts(recordID: UUID) async throws {
        try await store.deleteReceipts(recordID: recordID)
        notifyChanges()
    }

    public func deleteRecord(id: UUID) async throws {
        try await store.deleteRecord(id: id)
        notifyChanges()
    }

    public func fetchTags() async throws -> [WalletTag] { try await store.fetchTags() }

    public func createTag(name: String, color: TagColor) async throws {
        try await store.createTag(name: name, color: color)
        notifyChanges()
    }

    public func updateTag(id: UUID, name: String, color: TagColor) async throws {
        try await store.updateTag(id: id, name: name, color: color)
        notifyChanges()
    }

    public func deleteTag(id: UUID) async throws {
        try await store.deleteTag(id: id)
        notifyChanges()
    }

    public func fetchCategories() async throws -> [WalletCategory] { try await store.fetchCategories() }

    public func createCategory(name: String, nature: CategoryNature, parentID: UUID?) async throws {
        try await store.createCategory(name: name, nature: nature, parentID: parentID)
        notifyChanges()
    }

    public func updateCategory(id: UUID, name: String, nature: CategoryNature) async throws {
        try await store.updateCategory(id: id, name: name, nature: nature)
        notifyChanges()
    }

    public func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        try await store.updateAccount(id: id, name: name, type: type, settings: settings)
        notifyChanges()
    }

    public func accountDeletionImpact(id: UUID) async throws -> AccountDeletionImpact {
        try await store.accountDeletionImpact(id: id)
    }

    public func deleteAccount(id: UUID, strategy: AccountDeletionStrategy) async throws {
        try await store.deleteAccount(id: id, strategy: strategy)
        notifyChanges()
    }

    public func deleteCategory(id: UUID, strategy: CategoryDeletionStrategy) async throws {
        try await store.deleteCategory(id: id, strategy: strategy)
        notifyChanges()
    }

    public func createAccount(_ account: Account) async throws {
        try await store.createAccount(account)
        notifyChanges()
    }

    public func add(_ entry: WalletEntry) async throws {
        try await store.add(entry)
        notifyChanges()
    }

    public func delete(ids: Set<UUID>) async throws {
        try await store.delete(ids: ids)
        notifyChanges()
    }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.observers.removeValue(forKey: id) }
        }
        return stream
    }

    private func notifyChanges() {
        for observer in observers.values { observer.yield(()) }
    }

    deinit {
        for observer in observers.values { observer.finish() }
    }
}
