import Foundation

@MainActor
public protocol CategoryRepository: AnyObject {
    /// Adds missing starter IDs without replacing existing user edits, then fetches the hierarchy.
    func fetchCategories() async throws -> [WalletCategory]
    func createCategory(name: String, nature: CategoryNature, parentID: UUID?) async throws
    func updateCategory(id: UUID, name: String, nature: CategoryNature) async throws
    func changes() -> AsyncStream<Void>
}
