import Foundation

@MainActor
public protocol WalletRepository: AnyObject {
    func fetchEntries() async throws -> [WalletEntry]
    func add(_ entry: WalletEntry) async throws
    func delete(ids: Set<UUID>) async throws
    /// Local and imported-store invalidations, with an independent stream per subscriber.
    func changes() -> AsyncStream<Void>
}
