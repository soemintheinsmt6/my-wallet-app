import CoreData
import Foundation

/// Decides whether a store change notice is news.
///
/// `NSPersistentStoreRemoteChange` is posted for every save to the store, this app's own included,
/// not only for iCloud imports. Each of the app's own writes already sends a precise notice through
/// the repository, so reacting to the remote notice as well made every save reload the whole wallet.
/// This reads the store's persistent history since the last check and reports foreign changes only.
///
/// A transaction counts as the app's own only when this process wrote it without an author, which is
/// how a SwiftData `ModelContext` save is recorded. CloudKit's mirroring delegate signs what it
/// imports, another process has another name, and history that cannot be read counts as foreign, so
/// anything uncertain still reloads.
actor StoreHistoryFilter {
    /// Per coordinator, since a token only has meaning within its own store.
    private var lastTokens: [ObjectIdentifier: NSPersistentHistoryToken] = [:]
    /// The first check only looks at history written since launch, not the store's whole past.
    private let launchDate = Date()
    private let processName = ProcessInfo.processInfo.processName

    /// True when history since the last check holds any transaction the app did not write itself.
    func hasForeignChanges(in coordinator: UncheckedCoordinator) async -> Bool {
        let key = ObjectIdentifier(coordinator.value)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator.value
        let since = lastTokens[key]
        let launchDate = launchDate
        let processName = processName
        let outcome: (foreign: Bool, token: UncheckedToken?) = await context.perform {
            // A coordinator whose stores are gone, such as one torn down after posting, holds no
            // data to change; only a live store's unreadable history counts as foreign.
            guard context.persistentStoreCoordinator?.persistentStores.isEmpty == false else { return (false, nil) }
            let request = since.map { NSPersistentHistoryChangeRequest.fetchHistory(after: $0) }
                ?? NSPersistentHistoryChangeRequest.fetchHistory(after: launchDate)
            request.resultType = .transactionsOnly
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                return (true, nil)
            }
            let foreign = transactions.contains { $0.author != nil || $0.processID != processName }
            return (foreign, transactions.last.map { UncheckedToken(value: $0.token) })
        }
        if let token = outcome.token { lastTokens[key] = token.value }
        return outcome.foreign
    }
}

/// The coordinator from a notification, passed to the actor. Persistent store coordinators are
/// safe to use from a context bound to them on its own queue, which is all this does.
struct UncheckedCoordinator: @unchecked Sendable {
    let value: NSPersistentStoreCoordinator
}

/// History tokens are immutable values.
struct UncheckedToken: @unchecked Sendable {
    let value: NSPersistentHistoryToken
}
