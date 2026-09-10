import Foundation

public enum RecordKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case expense, income, transfer
    public var id: String { rawValue }
}

public enum PaymentType: String, CaseIterable, Codable, Sendable, Identifiable {
    case unspecified, cash, debitCard, creditCard, bankTransfer, mobilePayment, cheque, other
    public var id: String { rawValue }
}

public struct RecordDraft: Sendable, Equatable, Codable {
    public var kind: RecordKind = .expense
    public var accountID: UUID?
    public var destinationAccountID: UUID?
    public var amount: Decimal = 0
    public var receivedAmount: Decimal?
    public var categoryID: UUID?
    public var date: Date = Date()
    public var tagIDs: Set<UUID> = []
    public var note: String = ""
    public var payee: String = ""
    public var paymentType: PaymentType = .unspecified
    public var photoData: Data?
    public var recurrence: RecurrenceRule?
    /// Units of the home currency per one unit of this record's currency, when the user pins the
    /// rate for this record instead of using the downloaded one. `nil` means use market rates.
    public var manualRate: Decimal?

    public init() {}

    public func validate(allowUncategorized: Bool = false) throws {
        try recurrence?.validate(start: date)
        guard accountID != nil else { throw RecordValidationError.accountRequired }
        try Self.validateAmount(amount)
        if kind == .transfer {
            guard let destinationAccountID, destinationAccountID != accountID else { throw RecordValidationError.invalidTransfer }
            if let receivedAmount { try Self.validateAmount(receivedAmount) }
        } else if categoryID == nil && !allowUncategorized { throw RecordValidationError.categoryRequired }
        if let manualRate { guard manualRate > 0, manualRate.isFinite else { throw RecordValidationError.invalidRate } }
        guard note.count <= 2000, payee.count <= 120 else { throw RecordValidationError.textTooLong }
        guard (photoData?.count ?? 0) <= 5 * 1024 * 1024 else { throw RecordValidationError.photoTooLarge }
        guard date.timeIntervalSince1970.isFinite else { throw RecordValidationError.invalidDate }
    }

    public static func validateAmount(_ value: Decimal) throws {
        guard !value.isNaN, value > 0, value < Decimal(string: "1000000000000000000")! else {
            throw RecordValidationError.invalidAmount
        }
        var amount = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 8, .plain)
        guard value == rounded else { throw RecordValidationError.invalidAmount }
    }
}

public struct WalletRecord: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Fetch results omit photo bytes; load attachments separately when opening a record.
    public let draft: RecordDraft
    public let currencyCode: String
    public let destinationCurrencyCode: String?
    public let hasPhoto: Bool

    public init(id: UUID, draft: RecordDraft, currencyCode: String, destinationCurrencyCode: String? = nil, hasPhoto: Bool = false) {
        self.id = id
        self.draft = draft
        self.currencyCode = currencyCode
        self.destinationCurrencyCode = destinationCurrencyCode
        self.hasPhoto = hasPhoto
    }
}

public enum RecordValidationError: LocalizedError {
    case accountRequired, categoryRequired, invalidTransfer, invalidAmount, missingReference
    case receivedAmountRequired, textTooLong, photoTooLarge, invalidPhoto, invalidDate, saveInProgress
    case invalidRate

    public var errorDescription: String? {
        switch self {
        case .accountRequired: "Choose an account."
        case .categoryRequired: "Choose a category or subcategory."
        case .invalidTransfer: "Choose two different accounts for the transfer."
        case .invalidAmount: "Enter an amount greater than zero, with up to 18 integer digits and 8 decimal places."
        case .missingReference: "An account, category or label is no longer available. Refresh and choose again."
        case .receivedAmountRequired: "Enter the amount received in the destination account's currency."
        case .textTooLong: "Use up to 2,000 characters for the note and 120 for the payee."
        case .photoTooLarge: "Choose a photo smaller than 5 MB."
        case .invalidPhoto: "This photo could not be loaded. Choose another image."
        case .invalidDate: "Choose a valid date and time."
        case .saveInProgress: "A record is being saved. Please try again."
        case .invalidRate: "Enter an exchange rate greater than zero."
        }
    }
}
