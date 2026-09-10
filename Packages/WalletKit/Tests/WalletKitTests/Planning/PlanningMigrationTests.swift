import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain

@MainActor
struct PlanningMigrationTests {
    @Test func plansMigrateFromPhaseOneAndRoundTripSchedulesPhotosAndReceipts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let account = Account(name: "Existing", type: .cash, settings: AccountSettings(currentBalance: 100))
        let category = WalletCategory(name: "Existing category")
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func oldStore() throws {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self, TagRecord.self, TransactionRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(AccountRecord(account: account))
            context.insert(CategoryRecord(category: category))
            try context.save()
        }
        func open() throws -> WalletStore {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self, TagRecord.self, TransactionRecord.self,
                                 BudgetRecord.self, RecurringSeriesRecord.self, ScheduledOccurrenceRecord.self, BillReminderRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            return WalletStore(modelContainer: container)
        }
        func createPlans() async throws {
            let store = try open()
            #expect(try await store.fetchAccounts().first == account)
            var draft = RecordDraft()
            draft.accountID = account.id; draft.categoryID = category.id; draft.amount = Decimal(string: "1.23456789")!
            draft.date = now; draft.photoData = Data([1, 2, 3])
            draft.recurrence = RecurrenceRule(frequency: .daily, count: 3, timeZoneIdentifier: "UTC")
            try await store.createRecord(id: id, draft: draft)
            try await store.saveBudget(Budget(name: "Budget", amount: 50, categoryID: category.id))
            try await store.saveBillReminder(BillReminder(name: "Bill", amount: 5, accountID: account.id, categoryID: category.id))
            #expect(try await store.generateDueRecords(through: now.addingTimeInterval(86400)) == 1)
            try await store.deleteRecord(id: ScheduledOccurrence.identifier(owner: id, index: 1, kind: "recurring"))
        }
        try oldStore()
        try await createPlans()
        let reopened = try open()
        #expect(try await reopened.fetchBudgets().count == 1)
        #expect(try await reopened.fetchBillReminders().count == 1)
        #expect(try await reopened.fetchRecurringSeries().first?.template.photoData == Data([1, 2, 3]))
        #expect(try await reopened.fetchRecurringSeries().first?.template.amount == Decimal(string: "1.23456789"))
        #expect(try await reopened.fetchOccurrences().first?.completed == true)
        #expect(try await reopened.generateDueRecords(through: now.addingTimeInterval(86400)) == 0)
        #expect(try await reopened.fetchRecords().count == 1)
    }
}
