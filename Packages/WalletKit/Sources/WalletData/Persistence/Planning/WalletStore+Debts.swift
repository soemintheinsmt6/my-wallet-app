import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    // MARK: - Debts

    func fetchDebts() throws -> [Debt] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<DebtRecord>()).compactMap(\.debt)
    }

    func fetchDebtPayments() throws -> [DebtPayment] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<DebtPaymentRecord>()).compactMap(\.payment)
    }

    func saveDebt(_ debt: Debt) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = debt.id
        for existing in try context.fetch(FetchDescriptor<DebtRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        context.insert(DebtRecord(debt: debt))
        try context.save()
    }

    /// Deleting a debt deletes its payments; a payment without a debt could never be shown.
    func deleteDebt(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for existing in try context.fetch(FetchDescriptor<DebtRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        for payment in try context.fetch(FetchDescriptor<DebtPaymentRecord>(predicate: #Predicate { $0.debtID == id })) {
            context.delete(payment)
        }
        try context.save()
    }

    func saveDebtPayment(_ payment: DebtPayment) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = payment.id
        for existing in try context.fetch(FetchDescriptor<DebtPaymentRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        context.insert(DebtPaymentRecord(payment: payment))
        try context.save()
    }

    func deleteDebtPayment(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for existing in try context.fetch(FetchDescriptor<DebtPaymentRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        try context.save()
    }

    // MARK: - Goals

    func fetchGoals() throws -> [SavingsGoal] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<SavingsGoalRecord>()).compactMap(\.goal)
    }

    func fetchGoalContributions() throws -> [GoalContribution] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<GoalContributionRecord>()).compactMap(\.contribution)
    }

    func saveGoal(_ goal: SavingsGoal) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = goal.id
        for existing in try context.fetch(FetchDescriptor<SavingsGoalRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        context.insert(SavingsGoalRecord(goal: goal))
        try context.save()
    }

    func deleteGoal(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for existing in try context.fetch(FetchDescriptor<SavingsGoalRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        for contribution in try context.fetch(FetchDescriptor<GoalContributionRecord>(predicate: #Predicate { $0.goalID == id })) {
            context.delete(contribution)
        }
        try context.save()
    }

    func saveGoalContribution(_ contribution: GoalContribution) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = contribution.id
        for existing in try context.fetch(FetchDescriptor<GoalContributionRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        context.insert(GoalContributionRecord(contribution: contribution))
        try context.save()
    }

    func deleteGoalContribution(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for existing in try context.fetch(FetchDescriptor<GoalContributionRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        try context.save()
    }
}
