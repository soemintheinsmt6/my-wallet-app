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
        let changes = try recordBalanceChanges(in: context)
        var baseSettings = settings
        baseSettings.currentBalance -= changes[id, default: 0]
        for record in records { record.apply(name: name, type: type, settings: baseSettings) }
        try context.save()
    }

    func fetchAccounts() throws -> [Account] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AccountRecord>(sortBy: [SortDescriptor(\AccountRecord.createdAt)])
        let changes = try recordBalanceChanges(in: context)
        return try context.fetch(descriptor).map { record in
            let account = record.account
            var settings = account.settings
            settings.currentBalance += changes[account.id, default: 0]
            return Account(id: account.id, name: account.name, type: account.type, createdAt: account.createdAt, currencyCode: account.currencyCode, settings: settings)
        }
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
