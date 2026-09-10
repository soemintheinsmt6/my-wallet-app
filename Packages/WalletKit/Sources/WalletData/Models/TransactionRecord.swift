import Foundation
import SwiftData
import WalletDomain

@Model
final class TransactionRecord {
    var id: UUID = UUID()
    var kindValue: String = "expense"
    var accountID: UUID?
    var destinationAccountID: UUID?
    var amountValue: String = "0"
    var receivedAmountValue: String?
    var currencyCode: String = "USD"
    var destinationCurrencyCode: String?
    var categoryID: UUID?
    var date: Date = Date()
    var tagIDs: [UUID] = []
    var note: String = ""
    var payee: String = ""
    var paymentValue: String = "unspecified"
    /// Optional so the addition is a lightweight, CloudKit-compatible migration; existing records
    /// simply have no pinned rate and keep using market rates.
    var manualRateValue: String?
    var hasPhoto: Bool = false
    @Attribute(.externalStorage) var photoData: Data?

    init(id: UUID, draft: RecordDraft, currencyCode: String, destinationCurrencyCode: String?) {
        self.id = id
        apply(draft: draft, currencyCode: currencyCode, destinationCurrencyCode: destinationCurrencyCode)
    }

    func apply(draft: RecordDraft, currencyCode: String, destinationCurrencyCode: String?) {
        kindValue = draft.kind.rawValue
        accountID = draft.accountID
        destinationAccountID = draft.kind == .transfer ? draft.destinationAccountID : nil
        amountValue = NSDecimalNumber(decimal: draft.amount).stringValue
        receivedAmountValue = draft.kind == .transfer ? draft.receivedAmount.map { NSDecimalNumber(decimal: $0).stringValue } : nil
        self.currencyCode = currencyCode
        self.destinationCurrencyCode = destinationCurrencyCode
        categoryID = draft.categoryID
        date = draft.date
        tagIDs = draft.tagIDs.sorted { $0.uuidString < $1.uuidString }
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        payee = draft.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        paymentValue = draft.paymentType.rawValue
        manualRateValue = draft.manualRate.map { NSDecimalNumber(decimal: $0).stringValue }
        photoData = draft.photoData
        hasPhoto = draft.photoData != nil
    }

    var record: WalletRecord {
        var draft = RecordDraft()
        draft.kind = RecordKind(rawValue: kindValue) ?? .expense
        draft.accountID = accountID
        draft.destinationAccountID = destinationAccountID
        draft.amount = Decimal(string: amountValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        draft.receivedAmount = receivedAmountValue.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        draft.categoryID = categoryID
        draft.date = date
        draft.tagIDs = Set(tagIDs)
        draft.note = note
        draft.payee = payee
        draft.paymentType = PaymentType(rawValue: paymentValue) ?? .unspecified
        draft.manualRate = manualRateValue.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        return WalletRecord(id: id, draft: draft, currencyCode: currencyCode, destinationCurrencyCode: destinationCurrencyCode, hasPhoto: hasPhoto)
    }
}
