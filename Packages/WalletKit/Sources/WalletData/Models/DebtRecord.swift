import Foundation
import SwiftData
import WalletDomain

/// Debts and goals store their payload as Codable JSON, matching how the planning models already
/// persist their value types. Every property is defaulted, so these remain CloudKit-compatible
/// additive models.
@Model
final class DebtRecord {
    var id: UUID = UUID()
    var payload: Data?
    /// The photo lives in its own columns, as a record's does, so listing debts never reads it.
    /// Defaulted, so adding them is a lightweight, CloudKit-compatible migration.
    var hasPhoto: Bool = false
    @Attribute(.externalStorage) var photoData: Data?

    init(debt: Debt) {
        id = debt.id
        payload = try? JSONEncoder().encode(debt)
    }

    var debt: Debt? {
        guard let payload, var debt = try? JSONDecoder().decode(Debt.self, from: payload) else { return nil }
        debt.hasPhoto = hasPhoto
        return debt
    }

    func apply(photo change: DebtPhotoChange) {
        guard case .replace(let data) = change else { return }
        photoData = data
        hasPhoto = data != nil
    }
}

@Model
final class DebtPaymentRecord {
    var id: UUID = UUID()
    /// Kept as a column so payments for a deleted debt can be found without decoding every row.
    var debtID: UUID = UUID()
    var payload: Data?

    init(payment: DebtPayment) {
        id = payment.id
        debtID = payment.debtID
        payload = try? JSONEncoder().encode(payment)
    }

    var payment: DebtPayment? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(DebtPayment.self, from: payload)
    }
}

/// Its own model rather than a kind of payment, so an older build syncing these never mistakes
/// money added to a debt for money paid off it.
@Model
final class DebtAdditionRecord {
    var id: UUID = UUID()
    /// Kept as a column so additions for a deleted debt can be found without decoding every row.
    var debtID: UUID = UUID()
    var payload: Data?

    init(addition: DebtAddition) {
        id = addition.id
        debtID = addition.debtID
        payload = try? JSONEncoder().encode(addition)
    }

    var addition: DebtAddition? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(DebtAddition.self, from: payload)
    }
}

@Model
final class SavingsGoalRecord {
    var id: UUID = UUID()
    var payload: Data?

    init(goal: SavingsGoal) {
        id = goal.id
        payload = try? JSONEncoder().encode(goal)
    }

    var goal: SavingsGoal? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(SavingsGoal.self, from: payload)
    }
}

@Model
final class GoalContributionRecord {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var payload: Data?

    init(contribution: GoalContribution) {
        id = contribution.id
        goalID = contribution.goalID
        payload = try? JSONEncoder().encode(contribution)
    }

    var contribution: GoalContribution? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(GoalContribution.self, from: payload)
    }
}

@Model
final class RecordSplitRecord {
    var id: UUID = UUID()
    /// Kept as a column so a record's split can be found and removed with it.
    var recordID: UUID = UUID()
    var payload: Data?

    init(split: RecordSplit) {
        id = split.id
        recordID = split.recordID
        payload = try? JSONEncoder().encode(split)
    }

    var split: RecordSplit? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(RecordSplit.self, from: payload)
    }
}
