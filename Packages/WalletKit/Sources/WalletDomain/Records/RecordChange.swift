import Foundation

/// What a write did to the ledger, so screens holding every record, or balances derived from them,
/// can update the one that changed instead of reading the whole ledger back.
public enum RecordChange: Sendable, Equatable {
    /// One record was created or updated: `record` as stored now, `previous` as it was before, or
    /// `nil` when it is new. `version` is the store's ledger version after the write, or `nil` when
    /// not known.
    case saved(WalletRecord, previous: WalletRecord?, version: Int?)
    /// One record was deleted; `previous` is what was removed, or `nil` if it was already gone.
    case deleted(UUID, previous: WalletRecord?, version: Int?)
    /// Anything else, or a change whose extent is unknown: an iCloud import, generated or imported
    /// records, a reset, or an account or category edit that touches many records. Reload everything.
    case unknown

    /// The ledger version the write produced. A load that reports this version or later already
    /// includes the change.
    public var version: Int? {
        switch self {
        case .saved(_, _, let version), .deleted(_, _, let version): version
        case .unknown: nil
        }
    }
}

public extension RecordDraft {
    /// How this record moves account balances: income adds to its account, everything else takes
    /// from it, and a transfer also adds what arrived to its destination. The one rule both the
    /// stored balance and an in-memory update use, so the two cannot disagree.
    var balanceEffects: [UUID: Decimal] {
        var effects: [UUID: Decimal] = [:]
        if let accountID {
            effects[accountID, default: 0] += kind == .income ? amount : -amount
        }
        if kind == .transfer, let destinationAccountID {
            effects[destinationAccountID, default: 0] += receivedAmount ?? amount
        }
        return effects
    }
}

/// Applies a single-record change to lists already in memory.
public enum RecordChangeApplier {
    /// The records with `change` applied, still newest first, or `nil` for `.unknown`.
    ///
    /// Applying the same change twice leaves the list as one application does, so a screen can
    /// apply its own save at once and again when the change notice arrives.
    public static func records(_ records: [WalletRecord], applying change: RecordChange) -> [WalletRecord]? {
        switch change {
        case .unknown:
            return nil
        case .deleted(let id, _, _):
            guard let index = records.firstIndex(where: { $0.id == id }) else { return records }
            var updated = records
            updated.remove(at: index)
            return updated
        case .saved(let record, _, _):
            var updated = records
            if let index = updated.firstIndex(where: { $0.id == record.id }) {
                if updated[index] == record { return records }
                updated.remove(at: index)
            }
            updated.insert(record, at: insertionIndex(for: record.draft.date, in: updated))
            return updated
        }
    }

    /// The record `change` leaves behind, as `records` held it before, and after.
    public static func drafts(in records: [WalletRecord], for change: RecordChange) -> (before: RecordDraft?, after: RecordDraft?)? {
        switch change {
        case .unknown: return nil
        case .deleted(let id, _, _): return (records.first { $0.id == id }?.draft, nil)
        case .saved(let record, _, _): return (records.first { $0.id == record.id }?.draft, record.draft)
        }
    }

    /// The record before and after `change`, as the change itself reports them, for screens that
    /// hold balances but not records. Apply each change once.
    public static func drafts(reportedBy change: RecordChange) -> (before: RecordDraft?, after: RecordDraft?)? {
        switch change {
        case .unknown: return nil
        case .deleted(_, let previous, _): return (previous?.draft, nil)
        case .saved(let record, let previous, _): return (previous?.draft, record.draft)
        }
    }

    /// The accounts with balances moved by the difference between `before` and `after`.
    public static func accounts(_ accounts: [Account], movingFrom before: RecordDraft?, to after: RecordDraft?) -> [Account] {
        var delta = after?.balanceEffects ?? [:]
        for (id, amount) in before?.balanceEffects ?? [:] { delta[id, default: 0] -= amount }
        delta = delta.filter { $0.value != 0 }
        guard !delta.isEmpty else { return accounts }
        return accounts.map { account in
            guard let change = delta[account.id] else { return account }
            var settings = account.settings
            settings.currentBalance += change
            return Account(id: account.id, name: account.name, type: account.type, createdAt: account.createdAt,
                           currencyCode: account.currencyCode, settings: settings)
        }
    }

    /// Newest first: after every record at least as new, so a new record lands among others of its
    /// moment without reordering them. Binary search, since the list can run to tens of thousands.
    private static func insertionIndex(for date: Date, in records: [WalletRecord]) -> Int {
        var low = 0
        var high = records.count
        while low < high {
            let middle = (low + high) / 2
            if records[middle].draft.date >= date { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
