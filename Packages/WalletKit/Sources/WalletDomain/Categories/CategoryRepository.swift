import Foundation

@MainActor
public protocol CategoryRepository: AnyObject {
    /// Adds missing starter IDs without replacing edits or deleted IDs, then fetches the visible hierarchy.
    func fetchCategories() async throws -> [WalletCategory]
    func createCategory(name: String, nature: CategoryNature, parentID: UUID?) async throws
    func updateCategory(id: UUID, name: String, nature: CategoryNature) async throws
    /// Sets the category's icon, or returns it to the starter icon when `symbolName` is `nil`.
    func setCategorySymbol(id: UUID, symbolName: String?) async throws
    func deleteCategory(id: UUID, strategy: CategoryDeletionStrategy) async throws
    func changes() -> AsyncStream<Void>
}

public enum CategoryDeletionStrategy: Sendable {
    case deleteSubcategories
    case reassignSubcategories(to: UUID)
}
