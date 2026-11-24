import Foundation

/// Which way the money is owed.
public enum DebtDirection: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Someone owes the user.
    case owedToMe
    /// The user owes someone.
    case iOwe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .owedToMe: "They owe me"
        case .iOwe: "I owe them"
        }
    }

    /// Settling a debt someone owes the user brings money in; settling one the user owes sends it out.
    public var settlementKind: RecordKind {
        switch self {
        case .owedToMe: .income
        case .iOwe: .expense
        }
    }

    /// When the money changes hands as the debt is made: borrowing puts it into an account,
    /// lending takes it out. Settling moves it back the other way.
    public var openingIncreasesBalance: Bool { self == .iOwe }
}

/// Money owed to or by another person.
///
/// Deliberately not an account: a debt is a claim, not a balance the user holds, and folding it
/// into account balances would misstate what is actually in the wallet.
public struct Debt: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var person: String
    public var direction: DebtDirection
    /// The original amount owed, before any payments.
    public var amount: Decimal
    public var currencyCode: String
    public var dueDate: Date?
    public var note: String
    public var createdAt: Date
    public var notificationsEnabled: Bool
    /// The balance adjustment written when the money changed hands as the debt was made: lent out
    /// of an account, or borrowed into one. While it is set, settling records the money's return as
    /// an adjustment too, so a loan never counts as income or spending; without it, settling records
    /// income or an expense, for debts whose money was already recorded (a shared bill, say).
    ///
    /// Optional in the stored JSON, so debts saved before it existed decode with none.
    public var openingRecordID: UUID?
    /// Whether a photo is attached. The bytes are stored beside the debt rather than in it, so
    /// loading the debt list never reads them; fetch them with `DebtUseCases.photo(id:)`.
    /// Not encoded: the store sets it from its own column.
    public var hasPhoto: Bool

    /// Whether the money was recorded moving when the debt was made.
    public var movedMoney: Bool { openingRecordID != nil }

    private enum CodingKeys: String, CodingKey {
        case id, person, direction, amount, currencyCode, dueDate, note, createdAt, notificationsEnabled,
             openingRecordID
    }

    public init(id: UUID = UUID(), person: String = "", direction: DebtDirection = .owedToMe,
                amount: Decimal = 0, currencyCode: String = "USD", dueDate: Date? = nil,
                note: String = "", createdAt: Date = Date(), notificationsEnabled: Bool = false,
                openingRecordID: UUID? = nil, hasPhoto: Bool = false) {
        self.id = id
        self.person = person
        self.direction = direction
        self.amount = amount
        self.currencyCode = currencyCode
        self.dueDate = dueDate
        self.note = note
        self.createdAt = createdAt
        self.notificationsEnabled = notificationsEnabled
        self.openingRecordID = openingRecordID
        self.hasPhoto = hasPhoto
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        person = try container.decode(String.self, forKey: .person)
        direction = try container.decode(DebtDirection.self, forKey: .direction)
        amount = try container.decode(Decimal.self, forKey: .amount)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        note = try container.decode(String.self, forKey: .note)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        openingRecordID = try container.decodeIfPresent(UUID.self, forKey: .openingRecordID)
        hasPhoto = false
    }

    public func validate() throws {
        guard !person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              person.count <= 80 else { throw DebtError.invalidPerson }
        try RecordDraft.validateAmount(amount)
        guard note.count <= 2000 else { throw DebtError.noteTooLong }
        guard Locale.commonISOCurrencyCodes.contains(currencyCode) else { throw DebtError.invalidCurrency }
        if let dueDate { guard dueDate.timeIntervalSince1970.isFinite else { throw DebtError.invalidDueDate } }
    }
}

/// A payment against a debt. Several may exist, so a debt can be settled piece by piece.
public struct DebtPayment: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var debtID: UUID
    public var amount: Decimal
    public var date: Date
    /// The ledger record this payment created, when the user chose to create one.
    public var recordID: UUID?

    public init(id: UUID = UUID(), debtID: UUID, amount: Decimal, date: Date = Date(),
                recordID: UUID? = nil) {
        self.id = id
        self.debtID = debtID
        self.amount = amount
        self.date = date
        self.recordID = recordID
    }
}

/// More money lent or borrowed on an existing debt, so the same person's debt grows in steps with
/// each step kept, rather than its amount being edited over.
public struct DebtAddition: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var debtID: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String
    /// The balance adjustment written when this money changed hands, for a debt whose money moved.
    public var recordID: UUID?

    public init(id: UUID = UUID(), debtID: UUID, amount: Decimal, date: Date = Date(), note: String = "",
                recordID: UUID? = nil) {
        self.id = id
        self.debtID = debtID
        self.amount = amount
        self.date = date
        self.note = note
        self.recordID = recordID
    }
}

/// One step in a debt's history, oldest first: the money it started with, each addition, each
/// payment.
public enum DebtEntry: Identifiable, Sendable, Equatable {
    case opening(Debt)
    case addition(DebtAddition)
    case payment(DebtPayment)

    public var id: UUID {
        switch self {
        case .opening(let debt): debt.id
        case .addition(let addition): addition.id
        case .payment(let payment): payment.id
        }
    }

    public var date: Date {
        switch self {
        case .opening(let debt): debt.createdAt
        case .addition(let addition): addition.date
        case .payment(let payment): payment.date
        }
    }

    public var amount: Decimal {
        switch self {
        case .opening(let debt): debt.amount
        case .addition(let addition): addition.amount
        case .payment(let payment): payment.amount
        }
    }

    public var recordID: UUID? {
        switch self {
        case .opening(let debt): debt.openingRecordID
        case .addition(let addition): addition.recordID
        case .payment(let payment): payment.recordID
        }
    }
}

/// One entry of a debt's history with the balance it left.
public struct DebtHistoryStep: Sendable, Equatable {
    public let entry: DebtEntry
    public let balance: Decimal
}

public enum DebtError: LocalizedError, Equatable {
    case invalidPerson
    case invalidCurrency
    case invalidDueDate
    case noteTooLong
    case paymentExceedsOutstanding
    case invalidPaymentAmount
    case invalidAdditionAmount
    case busy

    public var errorDescription: String? {
        switch self {
        case .invalidPerson: "Enter a name of up to 80 characters."
        case .invalidCurrency: "Choose a supported currency."
        case .invalidDueDate: "Choose a valid due date."
        case .noteTooLong: "Use up to 2,000 characters for the note."
        case .paymentExceedsOutstanding: "That is more than is still outstanding."
        case .invalidPaymentAmount: "Enter a payment greater than zero."
        case .invalidAdditionAmount: "Enter an amount greater than zero."
        case .busy: "A debt is being saved. Please try again."
        }
    }
}

/// A debt together with what has been added to it and paid against it.
public struct DebtProgress: Identifiable, Sendable, Equatable {
    public let debt: Debt
    public let payments: [DebtPayment]
    public let additions: [DebtAddition]

    public var id: UUID { debt.id }
    public var paid: Decimal { payments.reduce(0) { $0 + $1.amount } }
    /// The original amount plus everything lent or borrowed since.
    public var total: Decimal { additions.reduce(debt.amount) { $0 + $1.amount } }
    public var outstanding: Decimal { max(0, total - paid) }
    public var isSettled: Bool { outstanding == 0 }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        let value = NSDecimalNumber(decimal: paid / total).doubleValue
        return min(1, max(0, value))
    }

    /// The debt's history, oldest first. On the same instant the opening comes first, then
    /// additions, then payments, so a running balance never dips below zero part-way.
    public var entries: [DebtEntry] {
        let all = [DebtEntry.opening(debt)] + additions.map(DebtEntry.addition) + payments.map(DebtEntry.payment)
        return all.enumerated().sorted { first, second in
            first.element.date != second.element.date
                ? first.element.date < second.element.date : first.offset < second.offset
        }.map(\.element)
    }

    /// The entries oldest first, each with what was still owed once it was taken.
    public var history: [DebtHistoryStep] {
        var balance = Decimal.zero
        return entries.map { entry in
            if case .payment = entry { balance -= entry.amount } else { balance += entry.amount }
            return DebtHistoryStep(entry: entry, balance: max(0, balance))
        }
    }

    public var isOverdue: Bool {
        guard let due = debt.dueDate, !isSettled else { return false }
        return due < Date()
    }

    public init(debt: Debt, payments: [DebtPayment], additions: [DebtAddition] = []) {
        self.debt = debt
        self.payments = payments.sorted { $0.date < $1.date }
        self.additions = additions.sorted { $0.date < $1.date }
    }
}

/// What one person owes the user, or is owed, netted across their debts in one currency.
public struct PersonBalance: Identifiable, Sendable, Equatable {
    public let person: String
    public let currencyCode: String
    /// Positive means they owe the user; negative means the user owes them.
    public let net: Decimal
    public let debts: [DebtProgress]

    public var id: String { "\(person.lowercased())|\(currencyCode)" }
    public var isSettled: Bool { net == 0 }

    public init(person: String, currencyCode: String, net: Decimal, debts: [DebtProgress]) {
        self.person = person
        self.currencyCode = currencyCode
        self.net = net
        self.debts = debts
    }
}

/// What saving a debt does to its photo: an edit that never touched the photo leaves it alone, so the
/// editor need not load it just to write it back.
public enum DebtPhotoChange: Sendable, Equatable {
    case keep
    /// Attaches this photo, or with `nil` removes the one attached.
    case replace(Data?)
}

@MainActor
public protocol DebtRepository: AnyObject {
    func fetchDebts() async throws -> [Debt]
    func fetchDebtPayments() async throws -> [DebtPayment]
    func debtPhoto(id: UUID) async throws -> Data?
    func saveDebt(_ debt: Debt, photo: DebtPhotoChange) async throws
    func deleteDebt(id: UUID) async throws
    func saveDebtPayment(_ payment: DebtPayment) async throws
    func deleteDebtPayment(id: UUID) async throws
    func fetchDebtAdditions() async throws -> [DebtAddition]
    func saveDebtAddition(_ addition: DebtAddition) async throws
    func deleteDebtAddition(id: UUID) async throws
}

@MainActor
public struct DebtUseCases {
    private let repository: any DebtRepository

    public init(repository: any DebtRepository) { self.repository = repository }

    public func load() async throws -> [DebtProgress] {
        let debts = try await repository.fetchDebts()
        let payments = try await repository.fetchDebtPayments()
        let additions = try await repository.fetchDebtAdditions()
        return Self.progress(debts: debts, payments: payments, additions: additions)
    }

    public func save(_ debt: Debt, photo: DebtPhotoChange = .keep) async throws {
        var value = debt
        value.person = debt.person.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = debt.note.trimmingCharacters(in: .whitespacesAndNewlines)
        try value.validate()
        if case .replace(let data?) = photo, data.count > 5 * 1024 * 1024 {
            throw RecordValidationError.photoTooLarge
        }
        try await repository.saveDebt(value, photo: photo)
    }

    /// The attached photo's bytes, or `nil` when there is none.
    public func photo(id: UUID) async throws -> Data? { try await repository.debtPhoto(id: id) }

    public func delete(id: UUID) async throws { try await repository.deleteDebt(id: id) }

    /// Records a payment, refusing anything beyond what is still outstanding so a debt can never
    /// be overpaid into a negative balance.
    public func pay(_ progress: DebtProgress, amount: Decimal, recordID: UUID? = nil,
                    date: Date = Date()) async throws {
        guard amount > 0 else { throw DebtError.invalidPaymentAmount }
        guard amount <= progress.outstanding else { throw DebtError.paymentExceedsOutstanding }
        try await repository.saveDebtPayment(
            DebtPayment(debtID: progress.debt.id, amount: amount, date: date, recordID: recordID))
    }

    public func deletePayment(id: UUID) async throws { try await repository.deleteDebtPayment(id: id) }

    /// Adds money lent or borrowed to an existing debt. A settled debt reopens by that much.
    public func add(_ addition: DebtAddition) async throws {
        guard addition.amount > 0 else { throw DebtError.invalidAdditionAmount }
        try RecordDraft.validateAmount(addition.amount)
        var value = addition
        value.note = addition.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.note.count <= 2000 else { throw DebtError.noteTooLong }
        try await repository.saveDebtAddition(value)
    }

    public func deleteAddition(id: UUID) async throws { try await repository.deleteDebtAddition(id: id) }

    // MARK: - Pure calculations

    /// Pure, so it needs no actor: callers off the main actor (and tests) can use it directly.
    public nonisolated static func progress(debts: [Debt], payments: [DebtPayment],
                                            additions: [DebtAddition] = []) -> [DebtProgress] {
        let byDebt = Dictionary(grouping: payments, by: \.debtID)
        let addedByDebt = Dictionary(grouping: additions, by: \.debtID)
        return debts
            .map { DebtProgress(debt: $0, payments: byDebt[$0.id] ?? [], additions: addedByDebt[$0.id] ?? []) }
            .sorted { first, second in
                // Outstanding debts first, then soonest due, then newest.
                if first.isSettled != second.isSettled { return !first.isSettled }
                switch (first.debt.dueDate, second.debt.dueDate) {
                case let (left?, right?) where left != right: return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: return first.debt.createdAt > second.debt.createdAt
                }
            }
    }

    /// Nets each person's debts, keeping currencies separate as everywhere else in the app.
    ///
    /// Settled debts stay in the grouping so their history remains visible, but contribute zero.
    public nonisolated static func balances(_ progress: [DebtProgress]) -> [PersonBalance] {
        let groups = Dictionary(grouping: progress) { entry in
            "\(entry.debt.person.lowercased())|\(entry.debt.currencyCode)"
        }
        return groups.values.map { entries in
            let net = entries.reduce(Decimal.zero) { total, entry in
                entry.debt.direction == .owedToMe ? total + entry.outstanding : total - entry.outstanding
            }
            return PersonBalance(person: entries[0].debt.person,
                                 currencyCode: entries[0].debt.currencyCode,
                                 net: net, debts: entries)
        }
        .sorted { first, second in
            // Anyone still owing or owed comes first, largest outstanding at the top.
            if first.isSettled != second.isSettled { return !first.isSettled }
            if abs(first.net) != abs(second.net) { return abs(first.net) > abs(second.net) }
            return first.person.localizedStandardCompare(second.person) == .orderedAscending
        }
    }
}
