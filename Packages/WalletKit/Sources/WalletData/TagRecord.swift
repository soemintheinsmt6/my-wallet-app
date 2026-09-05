import Foundation
import SwiftData
import WalletDomain

@Model
final class TagRecord {
    var id: UUID = UUID()
    var name: String = ""
    var colorValue: String = "blue"

    init(tag: WalletTag) {
        id = tag.id
        name = tag.name
        colorValue = tag.color.rawValue
    }

    var tag: WalletTag { WalletTag(id: id, name: name, color: TagColor(rawValue: colorValue) ?? .blue) }
}
