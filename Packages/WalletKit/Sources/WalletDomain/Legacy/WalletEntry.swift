import Foundation

/// Starter entity; add financial transaction fields when their requirements are defined.
public struct WalletEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date

    public init(id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
    }
}
