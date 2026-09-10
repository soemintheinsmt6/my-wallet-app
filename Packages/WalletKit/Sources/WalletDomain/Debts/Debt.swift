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

    public init(id: UUID = UUID(), person: String = "", direction: DebtDirection = .owedToMe,
                amount: Decimal = 0, currencyCode: String = "USD", dueDate: Date? = nil,
                note: String = "", createdAt: Date = Date(), notificationsEnabled: Bool = false) {
        self.id = id
        self.person = person
        self.direction = direction
        self.amount = amount
        self.currencyCode = currencyCode
        self.dueDate = dueDate
        self.note = note
        self.createdAt = createdAt
        self.notificationsEnabled = notificationsEnabled
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

public enum DebtError: LocalizedError, Equatable {
    case invalidPerson
    case invalidCurrency
    case invalidDueDate
    case noteTooLong
    case paymentExceedsOutstanding
    case invalidPaymentAmount
    case busy

    public var errorDescription: String? {
        switch self {
        case .invalidPerson: "Enter a name of up to 80 characters."
        case .invalidCurrency: "Choose a supported currency."
        case .invalidDueDate: "Choose a valid due date."
        case .noteTooLong: "Use up to 2,000 characters for the note."
        case .paymentExceedsOutstanding: "That is more than is still outstanding."
        case .invalidPaymentAmount: "Enter a payment greater than zero."
        case .busy: "A debt is being saved. Please try again."
        }
    }
}

/// A debt together with what has been paid against it.
public struct DebtProgress: Identifiable, Sendable, Equatable {
    public let debt: Debt
    public let payments: [DebtPayment]

    public var id: UUID { debt.id }
    public var paid: Decimal { payments.reduce(0) { $0 + $1.amount } }
    public var outstanding: Decimal { max(0, debt.amount - paid) }
    public var isSettled: Bool { outstanding == 0 }

    public var fraction: Double {
        guard debt.amount > 0 else { return 0 }
        let value = NSDecimalNumber(decimal: paid / debt.amount).doubleValue
        return min(1, max(0, value))
    }

    public var isOverdue: Bool {
        guard let due = debt.dueDate, !isSettled else { return false }
        return due < Date()
    }

    public init(debt: Debt, payments: [DebtPayment]) {
        self.debt = debt
        self.payments = payments.sorted { $0.date < $1.date }
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

@MainActor
public protocol DebtRepository: AnyObject {
    func fetchDebts() async throws -> [Debt]
    func fetchDebtPayments() async throws -> [DebtPayment]
    func saveDebt(_ debt: Debt) async throws
    func deleteDebt(id: UUID) async throws
    func saveDebtPayment(_ payment: DebtPayment) async throws
    func deleteDebtPayment(id: UUID) async throws
}

@MainActor
public struct DebtUseCases {
    private let repository: any DebtRepository

    public init(repository: any DebtRepository) { self.repository = repository }

    public func load() async throws -> [DebtProgress] {
        let debts = try await repository.fetchDebts()
        let payments = try await repository.fetchDebtPayments()
        return Self.progress(debts: debts, payments: payments)
    }

    public func save(_ debt: Debt) async throws {
        var value = debt
        value.person = debt.person.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = debt.note.trimmingCharacters(in: .whitespacesAndNewlines)
        try value.validate()
        try await repository.saveDebt(value)
    }

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

    // MARK: - Pure calculations

    /// Pure, so it needs no actor: callers off the main actor (and tests) can use it directly.
    public nonisolated static func progress(debts: [Debt], payments: [DebtPayment]) -> [DebtProgress] {
        let byDebt = Dictionary(grouping: payments, by: \.debtID)
        return debts
            .map { DebtProgress(debt: $0, payments: byDebt[$0.id] ?? []) }
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
