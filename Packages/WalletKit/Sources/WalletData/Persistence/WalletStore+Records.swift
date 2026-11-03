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

    /// The saved record, how it was before when it already existed, and the ledger version the save
    /// produced — what a change notice needs so screens can update balances without reading every record.
    typealias SavedRecord = (saved: WalletRecord, previous: WalletRecord?, version: Int)
    typealias DeletedRecord = (previous: WalletRecord?, version: Int)

    @discardableResult
    func createRecord(id: UUID, draft: RecordDraft) throws -> SavedRecord {
        try saveRecord(id: id, draft: draft, updating: false)
    }

    @discardableResult
    func updateRecord(id: UUID, draft: RecordDraft) throws -> SavedRecord {
        try saveRecord(id: id, draft: draft, updating: true)
    }

    /// Returns the record as it was, or `nil` when there was nothing to delete.
    @discardableResult
    func deleteRecord(id: UUID) throws -> DeletedRecord {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let matches = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id }))
        let previous = matches.first?.record
        for record in matches {
            record.photoData = nil
            context.delete(record)
        }
        // Scanned pages live in their own model, so they must be removed with the record.
        try deleteReceipts(recordID: id, in: context)
        try deleteSplits(recordID: id, in: context)
        try context.save()
        return (previous, advanceLedgerVersion())
    }

    /// Returns the record as stored — normalized, with its currencies resolved — read back by ID so
    /// screens can splice it in without fetching the whole ledger, and the record as it was before.
    private func saveRecord(id: UUID, draft: RecordDraft, updating: Bool) throws -> SavedRecord {
        try Task.checkCancellation()
        try draft.validate(allowUncategorized: updating && draft.categoryID == nil)
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let byID = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        // Mapped before the write, which edits the same object in place.
        let previous = try context.fetch(byID).first?.record
        try writeRecord(id: id, draft: draft, updating: updating, in: context)
        try context.save()
        guard let saved = try context.fetch(byID).first else { throw RecordValidationError.missingReference }
        return (saved.record, previous, advanceLedgerVersion())
    }

    func writeRecord(id: UUID, draft: RecordDraft, updating: Bool = false, in context: ModelContext) throws {
        try draft.validate(allowUncategorized: updating && draft.categoryID == nil)
        // A retried save of the same editor submission must not affect balances twice.
        let existing = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id }))
        if updating {
            guard !existing.isEmpty else { throw RecordValidationError.missingReference }
        } else if !existing.isEmpty { return }
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
            let categories = canonicalCategories(try context.fetch(FetchDescriptor<CategoryRecord>()))
            guard categories.contains(where: { $0.id == categoryID }) else {
                throw RecordValidationError.missingReference
            }
        }
        let labels = Set(try context.fetch(FetchDescriptor<TagRecord>()).map(\.id))
        guard draft.tagIDs.isSubset(of: labels) else { throw RecordValidationError.missingReference }
        if updating {
            for record in existing {
                record.apply(draft: normalized, currencyCode: source.currencyCode, destinationCurrencyCode: destinationCurrency)
            }
        } else {
            context.insert(TransactionRecord(id: id, draft: normalized, currencyCode: source.currencyCode, destinationCurrencyCode: destinationCurrency))
        }
        if !updating, let rule = draft.recurrence {
            let series = RecurringSeries(id: id, template: normalized, rule: rule)
            context.insert(try RecurringSeriesRecord(series))
        }
    }

    /// Derive balances from ledger entries, avoiding synced read-modify-write counters.
    func recordBalanceChanges(in context: ModelContext) throws -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]
        // The same rule an in-memory update applies, so a spliced balance always matches this one.
        for transaction in try context.fetch(FetchDescriptor<TransactionRecord>()) {
            for (account, amount) in transaction.record.draft.balanceEffects {
                balances[account, default: 0] += amount
            }
        }
        return balances
    }
}
