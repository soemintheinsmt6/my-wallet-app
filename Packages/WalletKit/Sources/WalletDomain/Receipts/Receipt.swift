import Foundation

/// One scanned page attached to a record.
///
/// Kept separate from the record's single `photoData` so a receipt can run to several pages
/// without turning the record row's fetch into an image download.
public struct Receipt: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordID: UUID
    /// Ordering within a multi-page scan, starting at zero.
    public let pageIndex: Int
    public let imageData: Data
    public let createdAt: Date

    public init(id: UUID = UUID(), recordID: UUID, pageIndex: Int, imageData: Data,
                createdAt: Date = Date()) {
        self.id = id
        self.recordID = recordID
        self.pageIndex = pageIndex
        self.imageData = imageData
        self.createdAt = createdAt
    }
}

public enum ReceiptError: LocalizedError, Equatable {
    case tooLarge
    case tooManyPages(Int)
    case emptyImage

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "Each receipt page must be smaller than 5 MB."
        case .tooManyPages(let limit): "A record can hold up to \(limit) receipt pages."
        case .emptyImage: "That scan produced no image."
        }
    }
}

@MainActor
public protocol ReceiptRepository: AnyObject {
    func fetchReceipts(recordID: UUID) async throws -> [Receipt]
    /// Counts without loading image bytes, for badges and gallery labels.
    func receiptPageCounts() async throws -> [UUID: Int]
    func saveReceipts(_ receipts: [Receipt]) async throws
    func deleteReceipt(id: UUID) async throws
    func deleteReceipts(recordID: UUID) async throws
}

@MainActor
public struct ReceiptUseCases {
    /// Enough for a long till receipt without letting one record dominate the store.
    public static let pageLimit = 12
    public static let maximumPageBytes = 5 * 1024 * 1024

    private let repository: any ReceiptRepository

    public init(repository: any ReceiptRepository) { self.repository = repository }

    public func load(recordID: UUID) async throws -> [Receipt] {
        try await repository.fetchReceipts(recordID: recordID).sorted { $0.pageIndex < $1.pageIndex }
    }

    public func pageCounts() async throws -> [UUID: Int] { try await repository.receiptPageCounts() }

    /// Appends pages to a record, numbering them after whatever is already stored.
    public func append(pages: [Data], to recordID: UUID) async throws {
        guard !pages.isEmpty else { return }
        for page in pages {
            guard !page.isEmpty else { throw ReceiptError.emptyImage }
            guard page.count <= Self.maximumPageBytes else { throw ReceiptError.tooLarge }
        }
        let existing = try await repository.fetchReceipts(recordID: recordID)
        guard existing.count + pages.count <= Self.pageLimit else {
            throw ReceiptError.tooManyPages(Self.pageLimit)
        }
        let start = (existing.map(\.pageIndex).max() ?? -1) + 1
        let receipts = pages.enumerated().map { offset, data in
            Receipt(recordID: recordID, pageIndex: start + offset, imageData: data)
        }
        try await repository.saveReceipts(receipts)
    }

    public func delete(id: UUID) async throws { try await repository.deleteReceipt(id: id) }

    public func deleteAll(recordID: UUID) async throws {
        try await repository.deleteReceipts(recordID: recordID)
    }
}
