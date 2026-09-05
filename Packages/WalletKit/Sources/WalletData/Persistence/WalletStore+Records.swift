import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchRecords() throws -> [WalletRecord] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\TransactionRecord.date, order: .reverse)])).map(\.record)
    }

    func recordPhoto(id: UUID) throws -> Data? {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first?.photoData
    }

    func createRecord(id: UUID, draft: RecordDraft) throws {
        try Task.checkCancellation()
        try draft.validate()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        // A retried save of the same editor submission must not affect balances twice.
        guard try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).isEmpty else { return }
        let accounts = try context.fetch(FetchDescriptor<AccountRecord>())
        guard let source = accounts.first(where: { $0.id == draft.accountID }) else { throw RecordValidationError.missingReference }
        var normalized = draft
        var destinationCurrency: String?
        if draft.kind == .transfer {
            guard let destination = accounts.first(where: { $0.id == draft.destinationAccountID }) else { throw RecordValidationError.missingReference }
            destinationCurrency = destination.currencyCode
            if destination.currencyCode == source.currencyCode { normalized.receivedAmount = draft.amount }
            else if draft.receivedAmount == nil { throw RecordValidationError.receivedAmountRequired }
        }
        if let categoryID = draft.categoryID {
            guard try !context.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == categoryID })).isEmpty else {
                throw RecordValidationError.missingReference
            }
        }
        let labels = Set(try context.fetch(FetchDescriptor<TagRecord>()).map(\.id))
        guard draft.tagIDs.isSubset(of: labels) else { throw RecordValidationError.missingReference }
        context.insert(TransactionRecord(id: id, draft: normalized, currencyCode: source.currencyCode, destinationCurrencyCode: destinationCurrency))
        try context.save()
    }

    /// Derive balances from immutable ledger entries, avoiding synced read-modify-write counters.
    func recordBalanceChanges(in context: ModelContext) throws -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]
        for transaction in try context.fetch(FetchDescriptor<TransactionRecord>()) {
            let draft = transaction.record.draft
            if let accountID = draft.accountID {
                balances[accountID, default: 0] += draft.kind == .income ? draft.amount : -draft.amount
            }
            if draft.kind == .transfer, let destination = draft.destinationAccountID {
                balances[destination, default: 0] += draft.receivedAmount ?? draft.amount
            }
        }
        return balances
    }
}
