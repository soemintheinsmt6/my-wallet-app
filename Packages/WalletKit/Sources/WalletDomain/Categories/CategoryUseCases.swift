import Foundation

public enum CategoryValidationError: LocalizedError {
    case invalidName
    case duplicateName
    case invalidParent
    case notFound
    case saveInProgress

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a name with 1 to 80 characters."
        case .duplicateName: "A category with this name already exists at this level. Choose another name."
        case .invalidParent: "Choose an existing top-level category for this subcategory."
        case .notFound: "This category is no longer available. Close the form and refresh."
        case .saveInProgress: "Another category is being saved. Please try again."
        }
    }
}

@MainActor
public struct CategoryUseCases {
    private let repository: any CategoryRepository

    public init(repository: any CategoryRepository) { self.repository = repository }

    public func load() async throws -> [WalletCategory] { try await repository.fetchCategories() }

    public func create(name: String, nature: CategoryNature, parentID: UUID? = nil) async throws {
        let name = try validatedName(name)
        try Task.checkCancellation()
        try await repository.createCategory(name: name, nature: nature, parentID: parentID)
    }

    public func update(id: UUID, name: String, nature: CategoryNature) async throws {
        let name = try validatedName(name)
        try Task.checkCancellation()
        try await repository.updateCategory(id: id, name: name, nature: nature)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { throw CategoryValidationError.invalidName }
        return trimmed
    }
}
