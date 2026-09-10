import Foundation

/// How a record's total is divided between the people involved.
public enum SplitMethod: String, CaseIterable, Codable, Sendable, Identifiable {
    case equally
    case amounts
    case percentages

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .equally: "Equally"
        case .amounts: "Exact amounts"
        case .percentages: "Percentages"
        }
    }
}

/// One person's stake in a split record.
public struct SplitParticipant: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    /// What this person owes of the total.
    public var share: Decimal
    /// What this person actually put in when the bill was paid.
    public var paid: Decimal

    /// Positive means they are owed; negative means they still owe.
    public var balance: Decimal { paid - share }

    public init(id: UUID = UUID(), name: String, share: Decimal = 0, paid: Decimal = 0) {
        self.id = id
        self.name = name
        self.share = share
        self.paid = paid
    }
}

/// A record divided between people.
///
/// The user themselves is always a participant, named by `ownerName`, so "who paid and who owes"
/// has a complete picture rather than only listing other people.
public struct RecordSplit: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var recordID: UUID
    public var method: SplitMethod
    public var participants: [SplitParticipant]
    public var currencyCode: String
    /// Which participant is the wallet's owner.
    public var ownerParticipantID: UUID?

    public init(id: UUID = UUID(), recordID: UUID, method: SplitMethod = .equally,
                participants: [SplitParticipant] = [], currencyCode: String = "USD",
                ownerParticipantID: UUID? = nil) {
        self.id = id
        self.recordID = recordID
        self.method = method
        self.participants = participants
        self.currencyCode = currencyCode
        self.ownerParticipantID = ownerParticipantID
    }

    public var total: Decimal { participants.reduce(0) { $0 + $1.share } }
    public var totalPaid: Decimal { participants.reduce(0) { $0 + $1.paid } }

    /// The owner's own share, which is what should count toward their budgets.
    public var ownerShare: Decimal {
        guard let id = ownerParticipantID else { return total }
        return participants.first { $0.id == id }?.share ?? total
    }

    public func validate(against amount: Decimal) throws {
        guard participants.count >= 2 else { throw SplitError.needsTwoParticipants }
        guard participants.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw SplitError.invalidName }
        guard participants.allSatisfy({ $0.share >= 0 && $0.paid >= 0 }) else { throw SplitError.negativeShare }
        guard total == amount else { throw SplitError.sharesDoNotSumToTotal }
        guard totalPaid == amount else { throw SplitError.paymentsDoNotSumToTotal }
    }
}

public enum SplitError: LocalizedError, Equatable {
    case needsTwoParticipants
    case invalidName
    case negativeShare
    case sharesDoNotSumToTotal
    case paymentsDoNotSumToTotal
    case invalidPercentages

    public var errorDescription: String? {
        switch self {
        case .needsTwoParticipants: "A split needs at least two people."
        case .invalidName: "Give every person a name."
        case .negativeShare: "Shares and payments cannot be negative."
        case .sharesDoNotSumToTotal: "The shares must add up to the record's amount."
        case .paymentsDoNotSumToTotal: "What everyone paid must add up to the record's amount."
        case .invalidPercentages: "Percentages must add up to 100."
        }
    }
}

/// One payment that would settle part of a group's balances.
public struct SettlementSuggestion: Identifiable, Sendable, Equatable {
    public let from: String
    public let to: String
    public let amount: Decimal

    public var id: String { "\(from)→\(to)|\(amount)" }

    public init(from: String, to: String, amount: Decimal) {
        self.from = from
        self.to = to
        self.amount = amount
    }
}

/// Dividing totals and working out who should pay whom.
public enum SplitCalculator {
    /// One side of a settlement, named so the sort stays readable to the type-checker.
    private struct Party {
        let name: String
        var amount: Decimal
    }

    /// Divides a total equally, giving the remainder away one minor unit at a time.
    ///
    /// Splitting 10 three ways cannot be 3.33 each — that loses a cent. The first participants
    /// absorb the remainder so the shares always add back to the exact total.
    public static func equalShares(total: Decimal, count: Int, currencyCode: String = "USD") -> [Decimal] {
        guard count > 0 else { return [] }
        let digits = CurrencyConverter.fractionDigits(for: currencyCode)
        let scale = pow(Decimal(10), digits)
        var scaledTotal = total * scale
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaledTotal, 0, .plain)

        let units = NSDecimalNumber(decimal: rounded).intValue
        let base = units / count
        let remainder = units % count
        return (0..<count).map { index in
            let share = Decimal(base + (index < remainder ? 1 : 0))
            return share / scale
        }
    }

    /// Converts percentages into amounts, keeping the total exact.
    public static func shares(total: Decimal, percentages: [Decimal],
                              currencyCode: String = "USD") throws -> [Decimal] {
        guard !percentages.isEmpty else { return [] }
        guard percentages.allSatisfy({ $0 >= 0 }), percentages.reduce(0, +) == 100 else {
            throw SplitError.invalidPercentages
        }
        var shares = percentages.map { CurrencyConverter.rounded(total * $0 / 100, currencyCode: currencyCode) }
        // Rounding each share can drift from the total; the last participant absorbs the difference.
        let drift = total - shares.reduce(0, +)
        if drift != 0, let last = shares.indices.last { shares[last] += drift }
        return shares
    }

    /// Nets every participant across all splits, by name.
    public static func balances(_ splits: [RecordSplit]) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for split in splits {
            for participant in split.participants {
                let key = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
                totals[key, default: 0] += participant.balance
            }
        }
        return totals.filter { $0.value != 0 }
    }

    /// The fewest payments that settle a group.
    ///
    /// Repeatedly matches the largest creditor with the largest debtor. That is the standard greedy
    /// approach: it does not always find the theoretical minimum — that problem is NP-hard — but it
    /// never suggests more than one payment per person beyond the first, which is what matters when
    /// people are actually settling up.
    public static func settlements(from balances: [String: Decimal],
                                   currencyCode: String = "USD") -> [SettlementSuggestion] {
        // Largest first, ties broken by name so the same balances always produce the same plan.
        func ordered(_ entries: [Party]) -> [Party] {
            entries.sorted { left, right in
                if left.amount != right.amount { return left.amount > right.amount }
                return left.name < right.name
            }
        }
        var creditors = ordered(balances.filter { $0.value > 0 }.map { Party(name: $0.key, amount: $0.value) })
        var debtors = ordered(balances.filter { $0.value < 0 }.map { Party(name: $0.key, amount: -$0.value) })

        var suggestions: [SettlementSuggestion] = []
        var creditorIndex = 0
        var debtorIndex = 0
        while creditorIndex < creditors.count, debtorIndex < debtors.count {
            let amount = min(creditors[creditorIndex].amount, debtors[debtorIndex].amount)
            if amount > 0 {
                suggestions.append(SettlementSuggestion(from: debtors[debtorIndex].name,
                                                        to: creditors[creditorIndex].name,
                                                        amount: CurrencyConverter.rounded(amount, currencyCode: currencyCode)))
            }
            creditors[creditorIndex].amount -= amount
            debtors[debtorIndex].amount -= amount
            if creditors[creditorIndex].amount <= 0 { creditorIndex += 1 }
            if debtors[debtorIndex].amount <= 0 { debtorIndex += 1 }
        }
        return suggestions
    }
}

@MainActor
public protocol SplitRepository: AnyObject {
    func fetchSplits() async throws -> [RecordSplit]
    func saveSplit(_ split: RecordSplit) async throws
    func deleteSplit(recordID: UUID) async throws
}

@MainActor
public struct SplitUseCases {
    private let repository: any SplitRepository

    public init(repository: any SplitRepository) { self.repository = repository }

    public func load() async throws -> [RecordSplit] { try await repository.fetchSplits() }

    public func save(_ split: RecordSplit, recordAmount: Decimal) async throws {
        try split.validate(against: recordAmount)
        try await repository.saveSplit(split)
    }

    public func delete(recordID: UUID) async throws { try await repository.deleteSplit(recordID: recordID) }

    /// What each split record should contribute to the owner's budgets: their own share, not the
    /// whole bill they happened to put on their card.
    public nonisolated static func ownerShares(_ splits: [RecordSplit]) -> [UUID: Decimal] {
        Dictionary(splits.map { ($0.recordID, $0.ownerShare) }, uniquingKeysWith: { first, _ in first })
    }
}
