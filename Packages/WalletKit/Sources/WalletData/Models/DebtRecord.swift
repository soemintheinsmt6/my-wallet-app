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

    init(debt: Debt) {
        id = debt.id
        payload = try? JSONEncoder().encode(debt)
    }

    var debt: Debt? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(Debt.self, from: payload)
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
