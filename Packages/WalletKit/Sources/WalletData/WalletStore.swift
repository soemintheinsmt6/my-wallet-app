import Foundation
import SwiftData
import WalletDomain

@ModelActor
actor WalletStore {
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { throw AccountValidationError.accountNotFound }
        for record in records { record.apply(name: name, type: type, settings: settings) }
        try context.save()
    }

    func fetchAccounts() throws -> [Account] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AccountRecord>(sortBy: [SortDescriptor(\AccountRecord.createdAt)])
        return try context.fetch(descriptor).map(\.account)
    }

    func createAccount(_ account: Account) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.insert(AccountRecord(account: account))
        try context.save()
    }

    func fetchEntries() throws -> [WalletEntry] {
        // Fresh contexts see imported changes without retaining stale registered objects.
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.timestamp, order: .reverse)])
        return try context.fetch(descriptor).map(\.entry)
    }

    func add(_ entry: WalletEntry) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.insert(Item(entry: entry))
        try context.save()
    }

    func delete(ids: Set<UUID>) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let items = try context.fetch(FetchDescriptor<Item>())
        for item in items where ids.contains(item.id) { context.delete(item) }
        try context.save()
    }
}
