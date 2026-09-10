import SwiftData

extension WalletStore {
    func resetWalletData() throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        // Delete model instances in one save so normal CloudKit deletions are recorded.
        for budget in try context.fetch(FetchDescriptor<BudgetRecord>()) { context.delete(budget) }
        for series in try context.fetch(FetchDescriptor<RecurringSeriesRecord>()) { context.delete(series) }
        for occurrence in try context.fetch(FetchDescriptor<ScheduledOccurrenceRecord>()) { context.delete(occurrence) }
        for bill in try context.fetch(FetchDescriptor<BillReminderRecord>()) { context.delete(bill) }
        for record in try context.fetch(FetchDescriptor<TransactionRecord>()) { context.delete(record) }
        for tag in try context.fetch(FetchDescriptor<TagRecord>()) { context.delete(tag) }
        for category in try context.fetch(FetchDescriptor<CategoryRecord>()) { context.delete(category) }
        for account in try context.fetch(FetchDescriptor<AccountRecord>()) { context.delete(account) }
        for item in try context.fetch(FetchDescriptor<Item>()) { context.delete(item) }
        try Task.checkCancellation()
        try context.save()
    }
}
