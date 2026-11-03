import Foundation
import SwiftData
import WalletDomain

@ModelActor
actor WalletStore {
    /// Counts single-record writes (create, update, delete), raised in the same actor turn as the
    /// save. The actor runs one call at a time, so a read that reports version N includes every
    /// write numbered N or lower — which lets a screen holding balances tell whether a change
    /// notice is already in what it loaded. In memory only: it orders notices within one launch.
    private(set) var ledgerVersion = 0

    func advanceLedgerVersion() -> Int {
        ledgerVersion += 1
        return ledgerVersion
    }

    func fetchEntries() throws -> [WalletEntry] {
        // Fresh contexts see imported changes without retaining stale registered objects.
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.timestamp, order: .reverse)])
        return try context.fetch(descriptor).map(\.entry)
    }

    func add(_ entry: WalletEntry) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.insert(Item(entry: entry))
        try context.save()
    }

    func delete(ids: Set<UUID>) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let items = try context.fetch(FetchDescriptor<Item>())
        for item in items where ids.contains(item.id) { context.delete(item) }
        try context.save()
    }
}
