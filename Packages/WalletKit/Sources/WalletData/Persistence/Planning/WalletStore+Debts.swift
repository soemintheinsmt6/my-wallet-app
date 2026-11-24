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

    func debtPhoto(id: UUID) throws -> Data? {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<DebtRecord>(predicate: #Predicate { $0.id == id })).first?.photoData
    }

    /// Updates the debt in place, so a photo kept by `.keep` survives the edit. Any duplicate rows
    /// (from a sync conflict, say) are removed.
    func saveDebt(_ debt: Debt, photo: DebtPhotoChange) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = debt.id
        let existing = try context.fetch(FetchDescriptor<DebtRecord>(predicate: #Predicate { $0.id == id }))
        let record: DebtRecord
        if let first = existing.first {
            record = first
            record.payload = try JSONEncoder().encode(debt)
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            record = DebtRecord(debt: debt)
            context.insert(record)
        }
        record.apply(photo: photo)
        try context.save()
    }

    /// Deleting a debt deletes its payments and additions; neither could be shown without it.
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
        for addition in try context.fetch(FetchDescriptor<DebtAdditionRecord>(predicate: #Predicate { $0.debtID == id })) {
            context.delete(addition)
        }
        try context.save()
    }

    func fetchDebtAdditions() throws -> [DebtAddition] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<DebtAdditionRecord>()).compactMap(\.addition)
    }

    func saveDebtAddition(_ addition: DebtAddition) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = addition.id
        for existing in try context.fetch(FetchDescriptor<DebtAdditionRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
        }
        context.insert(DebtAdditionRecord(addition: addition))
        try context.save()
    }

    func deleteDebtAddition(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for existing in try context.fetch(FetchDescriptor<DebtAdditionRecord>(predicate: #Predicate { $0.id == id })) {
            context.delete(existing)
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

extension WalletStore {
    // MARK: - Splits

    func fetchSplits() throws -> [RecordSplit] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<RecordSplitRecord>()).compactMap(\.split)
    }

    func saveSplit(_ split: RecordSplit) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        // One split per record, so replace rather than accumulate.
        let recordID = split.recordID
        for existing in try context.fetch(FetchDescriptor<RecordSplitRecord>(predicate: #Predicate { $0.recordID == recordID })) {
            context.delete(existing)
        }
        context.insert(RecordSplitRecord(split: split))
        try context.save()
    }

    func deleteSplit(recordID: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        try deleteSplits(recordID: recordID, in: context)
        try context.save()
    }

    /// Shared with record deletion so a split never outlives the record it divides.
    func deleteSplits(recordID: UUID, in context: ModelContext) throws {
        for existing in try context.fetch(FetchDescriptor<RecordSplitRecord>(predicate: #Predicate { $0.recordID == recordID })) {
            context.delete(existing)
        }
    }
}
