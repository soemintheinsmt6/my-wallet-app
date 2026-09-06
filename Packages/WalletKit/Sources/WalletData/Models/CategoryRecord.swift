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

    init(category: WalletCategory, updatedAt: Date = Date()) {
        id = category.id
        parentID = category.parentID
        name = category.name
        natureValue = category.nature.rawValue
        sortOrder = category.sortOrder
        self.updatedAt = updatedAt
    }

    var category: WalletCategory {
        WalletCategory(id: id, parentID: parentID, name: name, nature: CategoryNature(rawValue: natureValue) ?? .none, sortOrder: sortOrder)
    }
}
