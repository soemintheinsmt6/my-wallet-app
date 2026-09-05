import Foundation
import SwiftData
import WalletDomain

// Preserve the starter entity name. CloudKit requires defaults and no unique constraints.
@Model
final class Item {
    var id: UUID = UUID()
    var timestamp: Date = Date()

    init(entry: WalletEntry) {
        id = entry.id
        timestamp = entry.timestamp
    }

    var entry: WalletEntry { WalletEntry(id: id, timestamp: timestamp) }
}
