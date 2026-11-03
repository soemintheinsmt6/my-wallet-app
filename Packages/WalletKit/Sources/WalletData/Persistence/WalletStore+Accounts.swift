import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    /// `settings.currentBalance` is the balance the user wants shown. A difference from today's
    /// balance is saved as a balance adjustment dated `date`, in the same save as the other edits,
    /// rather than by rewriting the base balance, which would silently change all past history.
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings, date: Date = Date()) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })
        let records = try context.fetch(descriptor)
        guard let stored = records.first else { throw AccountValidationError.accountNotFound }
        let base = stored.account.settings.currentBalance
        let difference = settings.currentBalance - (base + (try recordBalanceChanges(in: context))[id, default: 0])
        var baseSettings = settings
        baseSettings.currentBalance = base
        for record in records { record.apply(name: name, type: type, settings: baseSettings) }
        if difference != 0 {
            var adjustment = RecordDraft.adjustment(accountID: id, increase: difference > 0,
                                                    amount: abs(difference), date: date)
            adjustment.note = "Balance edited"
            try writeRecord(id: UUID(), draft: adjustment, in: context)
        }
        try context.save()
    }

    /// The accounts and the ledger version their balances include, read in one actor turn so no
    /// record write can land between the two.
    func fetchAccountsWithLedgerVersion() throws -> (accounts: [Account], ledgerVersion: Int) {
        (try fetchAccounts(), ledgerVersion)
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
