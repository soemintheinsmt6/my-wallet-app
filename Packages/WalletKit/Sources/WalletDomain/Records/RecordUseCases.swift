import Foundation

@MainActor
public struct RecordUseCases {
    private let repository: any RecordRepository
    public init(repository: any RecordRepository) { self.repository = repository }
    public func load() async throws -> [WalletRecord] { try await repository.fetchRecords() }
    public func create(id: UUID, draft: RecordDraft) async throws {
        try draft.validate()
        try Task.checkCancellation()
        try await repository.createRecord(id: id, draft: draft)
    }
    public func update(id: UUID, draft: RecordDraft) async throws {
        try draft.validate(allowUncategorized: true)
        try Task.checkCancellation()
        try await repository.updateRecord(id: id, draft: draft)
    }
    public func delete(id: UUID) async throws {
        try Task.checkCancellation()
        try await repository.deleteRecord(id: id)
    }
    public func photo(id: UUID) async throws -> Data? { try await repository.recordPhoto(id: id) }
    public func changes() -> AsyncStream<Void> { repository.changes() }
}
