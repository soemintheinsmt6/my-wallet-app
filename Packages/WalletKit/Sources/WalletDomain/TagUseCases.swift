import Foundation

public enum TagValidationError: LocalizedError {
    case invalidName
    case duplicateName
    case notFound
    case saveInProgress

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a label name with 1 to 80 characters."
        case .duplicateName: "A label with this name already exists. Choose another name."
        case .notFound: "This label no longer exists. Close the form and refresh."
        case .saveInProgress: "Another label is being saved. Please try again."
        }
    }
}

@MainActor
public struct TagUseCases {
    private let repository: any TagRepository

    public init(repository: any TagRepository) { self.repository = repository }

    public func load() async throws -> [WalletTag] { try await repository.fetchTags() }

    public func create(name: String, color: TagColor) async throws {
        let name = try validatedName(name)
        try Task.checkCancellation()
        try await repository.createTag(name: name, color: color)
    }

    public func update(id: UUID, name: String, color: TagColor) async throws {
        let name = try validatedName(name)
        try Task.checkCancellation()
        try await repository.updateTag(id: id, name: name, color: color)
    }

    public func delete(id: UUID) async throws {
        try Task.checkCancellation()
        try await repository.deleteTag(id: id)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { throw TagValidationError.invalidName }
        return trimmed
    }
}
