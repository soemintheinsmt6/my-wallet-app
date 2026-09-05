import Foundation

@MainActor
public struct WalletUseCases {
    private let repository: any WalletRepository

    public init(repository: any WalletRepository) {
        self.repository = repository
    }

    public func load() async throws -> [WalletEntry] {
        try await repository.fetchEntries()
    }

    public func add(timestamp: Date = Date()) async throws {
        try Task.checkCancellation()
        try await repository.add(WalletEntry(timestamp: timestamp))
    }

    public func delete(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        try Task.checkCancellation()
        try await repository.delete(ids: ids)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }
}
