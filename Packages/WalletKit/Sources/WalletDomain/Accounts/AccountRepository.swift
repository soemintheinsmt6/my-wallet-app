import Foundation

@MainActor
public protocol AccountRepository: AnyObject {
    func fetchAccounts() async throws -> [Account]
    func createAccount(_ account: Account) async throws
    /// Currency and creation metadata are immutable; updates contain only editable fields.
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws
    func changes() -> AsyncStream<Void>
}
