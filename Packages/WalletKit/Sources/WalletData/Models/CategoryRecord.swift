import Foundation
import SwiftData
import WalletDomain

@Model
final class CategoryRecord {
    var id: UUID = UUID()
    var parentID: UUID?
    var name: String = ""
    var deletionDate: Date?
    var natureValue: String = "none"
    var sortOrder: Int = 0
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    // Distinguishes physical replicas when two offline devices seed the same logical category.
    var replicaID: UUID = UUID()
    /// The chosen icon, `nil` for the starter one. Optional and defaulted, so it is a lightweight,
    /// CloudKit-compatible addition and existing categories simply have no choice yet.
    var symbolName: String?

    init(category: WalletCategory, updatedAt: Date = Date()) {
        id = category.id
        parentID = category.parentID
        name = category.name
        natureValue = category.nature.rawValue
        sortOrder = category.sortOrder
        symbolName = category.symbolName
        self.updatedAt = updatedAt
    }

    var category: WalletCategory {
        WalletCategory(id: id, parentID: parentID, name: name, nature: CategoryNature(rawValue: natureValue) ?? .none,
                       sortOrder: sortOrder, symbolName: symbolName)
    }
}
