import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchBudgets() throws -> [Budget] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<BudgetRecord>()).map { try $0.value }.sorted { $0.name < $1.name }
    }

    func saveBudget(_ budget: Budget) throws {
        try budget.validate()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        if let id = budget.categoryID {
            guard canonicalCategories(try context.fetch(FetchDescriptor<CategoryRecord>())).contains(where: { $0.id == id }) else {
                throw PlanningError.missingItem
            }
        }
        let id = budget.id
        let records = try context.fetch(FetchDescriptor<BudgetRecord>(predicate: #Predicate { $0.id == id }))
        if records.isEmpty { context.insert(try BudgetRecord(budget)) }
        else { for record in records { try record.apply(budget) } }
        try context.save()
    }

    func deleteBudget(id: UUID) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for budget in try context.fetch(FetchDescriptor<BudgetRecord>(predicate: #Predicate { $0.id == id })) { context.delete(budget) }
        try context.save()
    }
}
