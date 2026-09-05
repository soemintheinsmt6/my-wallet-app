@MainActor
public struct ResetWalletUseCase {
    private let repository: any WalletResetRepository

    public init(repository: any WalletResetRepository) {
        self.repository = repository
    }

    public func execute() async throws {
        try Task.checkCancellation()
        try await repository.resetWalletData()
    }
}
