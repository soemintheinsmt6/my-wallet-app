import Foundation

/// A full-fidelity JSON backup: accounts, categories, labels and records with their identifiers
/// intact, so a restore rebuilds the same wallet rather than an approximation.
///
/// Receipt images are deliberately excluded — they would dominate the file — which is stated in
/// the export UI.
public struct WalletArchive: Codable, Sendable, Equatable {
    /// Bumped when the shape changes so an older app can refuse a newer file.
    public static let currentVersion = 1

    public struct ArchivedAccount: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var type: AccountType
        public var currencyCode: String
        public var currentBalance: Decimal
        public var color: AccountColor
        public var excludeFromStats: Bool

        public init(account: Account) {
            id = account.id
            name = account.name
            type = account.type
            currencyCode = account.currencyCode
            currentBalance = account.settings.currentBalance
            color = account.settings.color
            excludeFromStats = account.settings.excludeFromStats
        }
    }

    public struct ArchivedCategory: Codable, Sendable, Equatable {
        public var id: UUID
        public var parentID: UUID?
        public var name: String
        public var nature: CategoryNature

        public init(category: WalletCategory) {
            id = category.id
            parentID = category.parentID
            name = category.name
            nature = category.nature
        }
    }

    public struct ArchivedTag: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var color: TagColor

        public init(tag: WalletTag) {
            id = tag.id
            name = tag.name
            color = tag.color
        }
    }

    public struct ArchivedRecord: Codable, Sendable, Equatable {
        public var id: UUID
        public var draft: RecordDraft
        public var currencyCode: String
        public var destinationCurrencyCode: String?

        public init(record: WalletRecord) {
            id = record.id
            var draft = record.draft
            // Photo bytes are never part of an archive.
            draft.photoData = nil
            self.draft = draft
            currencyCode = record.currencyCode
            destinationCurrencyCode = record.destinationCurrencyCode
        }
    }

    public var version: Int
    public var exportedAt: Date
    public var accounts: [ArchivedAccount]
    public var categories: [ArchivedCategory]
    public var tags: [ArchivedTag]
    public var records: [ArchivedRecord]

    public init(accounts: [Account], categories: [WalletCategory], tags: [WalletTag],
                records: [WalletRecord], exportedAt: Date = Date()) {
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.accounts = accounts.map(ArchivedAccount.init)
        self.categories = categories.map(ArchivedCategory.init)
        self.tags = tags.map(ArchivedTag.init)
        self.records = records.map(ArchivedRecord.init)
    }

    public static func encode(_ archive: WalletArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    public static func decode(_ data: Data) throws -> WalletArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(WalletArchive.self, from: data)
        guard archive.version <= currentVersion else { throw ArchiveError.unsupportedVersion(archive.version) }
        return archive
    }
}

public enum ArchiveError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This backup was written by a newer version of My Wallet (format \(version)). Update the app to restore it."
        }
    }
}
