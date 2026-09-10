import Foundation
import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    /// Declared in the app's Info.plist so dragged records are recognized as wallet records rather
    /// than as plain text that any view would accept.
    static let walletRecord = UTType(exportedAs: "com.app.My-Wallet.record")
}

/// A record being dragged, so it can be dropped onto a category to refile it.
///
/// Carries only the identifier: the receiving side already has the record and refiling it must go
/// through the normal save path, not through a copy of stale values.
public struct RecordTransfer: Codable, Sendable, Transferable, Equatable {
    public let recordID: UUID

    public init(recordID: UUID) { self.recordID = recordID }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .walletRecord)
    }
}
