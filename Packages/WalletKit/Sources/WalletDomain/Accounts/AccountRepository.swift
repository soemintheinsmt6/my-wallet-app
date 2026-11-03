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
    /// Record writes, in order. Balances come from the ledger, so a single saved or deleted record
    /// moves them by a known amount without reading every record again.
    func recordChanges() -> AsyncStream<RecordChange>
    /// Accounts and the ledger version their balances include. A record change whose version is
    /// at or below it is already counted; a later one is not. `nil` when the version is not known.
    func fetchAccountsWithLedgerVersion() async throws -> (accounts: [Account], ledgerVersion: Int?)
}

public extension AccountRepository {
    /// For repositories that cannot say what changed: every change asks for a full reload.
    func recordChanges() -> AsyncStream<RecordChange> { RecordChangeStreams.unknown(from: changes()) }

    /// Without a version, a screen cannot tell which changes a load includes, so it reloads instead.
    func fetchAccountsWithLedgerVersion() async throws -> (accounts: [Account], ledgerVersion: Int?) {
        (try await fetchAccounts(), nil)
    }
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
