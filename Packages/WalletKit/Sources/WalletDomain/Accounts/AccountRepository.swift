import Foundation

@MainActor
public protocol AccountRepository: AnyObject {
    func fetchAccounts() async throws -> [Account]
    func createAccount(_ account: Account) async throws
    /// Currency and creation metadata are immutable; updates contain only editable fields. A
    /// changed `settings.currentBalance` is recorded as a balance adjustment for the difference.
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws
    func accountDeletionImpact(id: UUID) async throws -> AccountDeletionImpact
    func deleteAccount(id: UUID, strategy: AccountDeletionStrategy) async throws
    func changes() -> AsyncStream<Void>
}

public enum AccountDeletionStrategy: String, CaseIterable, Sendable {
    case deleteRecords, keepRecords
}

public struct AccountDeletionImpact: Sendable {
    public let account: Account
    public let recordCount: Int
    public let transferCount: Int

    public init(account: Account, recordCount: Int, transferCount: Int) {
        self.account = account
        self.recordCount = recordCount
        self.transferCount = transferCount
    }
}
