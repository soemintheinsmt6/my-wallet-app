import Foundation
import SwiftData
import WalletDomain

/// A scanned receipt page.
///
/// A separate model rather than an array on `TransactionRecord`, so fetching the ledger never
/// pulls image bytes and a multi-page scan does not bloat every record read. Every property is
/// defaulted, keeping the addition CloudKit-compatible.
@Model
final class ReceiptRecord {
    var id: UUID = UUID()
    /// Plain identifier rather than a SwiftData relationship, matching how the rest of the schema
    /// links records so CloudKit sync stays simple.
    var recordID: UUID = UUID()
    var pageIndex: Int = 0
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var imageData: Data?

    init(receipt: Receipt) {
        id = receipt.id
        recordID = receipt.recordID
        pageIndex = receipt.pageIndex
        createdAt = receipt.createdAt
        imageData = receipt.imageData
    }

    /// `nil` when the image bytes are missing, so a half-synced page is skipped rather than shown
    /// as a blank page.
    var receipt: Receipt? {
        guard let imageData else { return nil }
        return Receipt(id: id, recordID: recordID, pageIndex: pageIndex,
                       imageData: imageData, createdAt: createdAt)
    }
}
