import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchReceipts(recordID: UUID) throws -> [Receipt] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ReceiptRecord>(
            predicate: #Predicate { $0.recordID == recordID },
            sortBy: [SortDescriptor(\.pageIndex)])
        return try context.fetch(descriptor).compactMap(\.receipt)
    }

    /// Counts pages without materializing image bytes.
    func receiptPageCounts() throws -> [UUID: Int] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<ReceiptRecord>()
        descriptor.propertiesToFetch = [\.recordID]
        var counts: [UUID: Int] = [:]
        for page in try context.fetch(descriptor) {
            counts[page.recordID, default: 0] += 1
        }
        return counts
    }

    func saveReceipts(_ receipts: [Receipt]) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for receipt in receipts {
            let id = receipt.id
            // Replace rather than duplicate if the same page identifier arrives again.
            for existing in try context.fetch(FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.id == id })) {
                existing.imageData = nil
                context.delete(existing)
            }
            context.insert(ReceiptRecord(receipt: receipt))
        }
        try context.save()
    }

    func deleteReceipt(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for page in try context.fetch(FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.id == id })) {
            // Clear external storage before deleting, as record photos do.
            page.imageData = nil
            context.delete(page)
        }
        try context.save()
    }

    func deleteReceipts(recordID: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        try deleteReceipts(recordID: recordID, in: context)
        try context.save()
    }

    /// Shared with record deletion so removing a record never leaves orphaned pages behind.
    func deleteReceipts(recordID: UUID, in context: ModelContext) throws {
        for page in try context.fetch(FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.recordID == recordID })) {
            page.imageData = nil
            context.delete(page)
        }
    }
}
