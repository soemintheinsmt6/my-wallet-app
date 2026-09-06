import Foundation

@MainActor
public protocol CategoryRepository: AnyObject {
    /// Adds missing starter IDs without replacing edits or deleted IDs, then fetches the visible hierarchy.
    func fetchCategories() async throws -> [WalletCategory]
    func createCategory(name: String, nature: CategoryNature, parentID: UUID?) async throws
    func updateCategory(id: UUID, name: String, nature: CategoryNature) async throws
    func deleteCategory(id: UUID, strategy: CategoryDeletionStrategy) async throws
    func changes() -> AsyncStream<Void>
}

public enum CategoryDeletionStrategy: Sendable {
    case deleteSubcategories
    case reassignSubcategories(to: UUID)
}
