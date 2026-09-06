import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
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
            return Account(
                id: account.id, name: account.name, type: account.type, createdAt: account.createdAt,
                currencyCode: account.currencyCode, settings: settings)
        }
    }

    func accountDeletionImpact(id: UUID) throws -> AccountDeletionImpact {
        guard let account = try fetchAccounts().first(where: { $0.id == id }) else {
            throw AccountValidationError.accountNotFound
        }
        let context = ModelContext(modelContainer)
        let records = try context.fetch(FetchDescriptor<TransactionRecord>()).filter {
            $0.accountID == id || $0.destinationAccountID == id
        }
        return AccountDeletionImpact(account: account, recordCount: records.count,
                                     transferCount: records.filter { $0.kindValue == RecordKind.transfer.rawValue }.count)
    }

    func deleteAccount(id: UUID, strategy: AccountDeletionStrategy) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for record in try context.fetch(FetchDescriptor<TransactionRecord>()) where record.accountID == id || record.destinationAccountID == id {
            switch strategy {
            case .deleteRecords:
                record.photoData = nil
                context.delete(record)
            case .keepRecords:
                // Retain the surviving transfer leg, currency snapshots, and attachment.
                if record.accountID == id { record.accountID = nil }
                if record.destinationAccountID == id { record.destinationAccountID = nil }
            }
        }
        for account in try context.fetch(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(account)
        }
        try context.save()
    }

    func createAccount(_ account: Account) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.insert(AccountRecord(account: account))
        try context.save()
    }
}
