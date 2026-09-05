import Foundation

public enum CategoryNature: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, must, need, want
    public var id: String { rawValue }
}

/// A root category has no parent. A subcategory refers to a root category's stable ID.
public struct WalletCategory: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let parentID: UUID?
    public let name: String
    public let nature: CategoryNature
    public let sortOrder: Int

    public init(id: UUID = UUID(), parentID: UUID? = nil, name: String, nature: CategoryNature = .none, sortOrder: Int = 0) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.nature = nature
        self.sortOrder = sortOrder
    }
}
