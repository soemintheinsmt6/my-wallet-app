import Foundation

public enum TagColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case blue, teal, green, yellow, orange, red, pink, purple, indigo, gray
    public var id: String { rawValue }
}

/// Reusable label identity; future records should reference the ID rather than copy its name.
public struct WalletTag: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let color: TagColor

    public init(id: UUID = UUID(), name: String, color: TagColor = .blue) {
        self.id = id
        self.name = name
        self.color = color
    }
}
