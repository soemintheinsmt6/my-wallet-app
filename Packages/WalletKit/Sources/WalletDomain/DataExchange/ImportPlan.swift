import Foundation

/// What a CSV import would do, worked out before anything is written.
///
/// Every parsed row lands in exactly one bucket, so the counts shown in the preview always add up
/// to the number of rows read.
public struct ImportPlan: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let row: RecordCSVRow
        public let accountID: UUID?
        public let destinationAccountID: UUID?
        public let categoryID: UUID?
        public let tagIDs: Set<UUID>
        /// Names that do not exist yet and would be created as labels.
        public let newLabelNames: [String]
        public let issue: Issue?

        public var isImportable: Bool { issue == nil }

        public init(id: UUID = UUID(), row: RecordCSVRow, accountID: UUID?, destinationAccountID: UUID?,
                    categoryID: UUID?, tagIDs: Set<UUID>, newLabelNames: [String], issue: Issue?) {
            self.id = id
            self.row = row
            self.accountID = accountID
            self.destinationAccountID = destinationAccountID
            self.categoryID = categoryID
            self.tagIDs = tagIDs
            self.newLabelNames = newLabelNames
            self.issue = issue
        }
    }

    /// Why a row cannot be imported as-is.
    public enum Issue: Sendable, Equatable {
        case duplicate
        case unknownAccount(String)
        case unknownDestinationAccount(String)
        case transferNeedsDestination
        case transferToSameAccount

        public var message: String {
            switch self {
            case .duplicate: "Already in your wallet"
            case .unknownAccount(let name): "No account named “\(name)”"
            case .unknownDestinationAccount(let name): "No destination account named “\(name)”"
            case .transferNeedsDestination: "Transfer has no destination account"
            case .transferToSameAccount: "Transfer source and destination match"
            }
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }

    public var importable: [Entry] { entries.filter(\.isImportable) }
    public var duplicates: [Entry] { entries.filter { $0.issue == .duplicate } }
    public var problems: [Entry] { entries.filter { $0.issue != nil && $0.issue != .duplicate } }
    /// Labels that would be created, de-duplicated across every row.
    public var labelsToCreate: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for entry in importable {
            for name in entry.newLabelNames where seen.insert(name.lowercased()).inserted {
                names.append(name)
            }
        }
        return names
    }

    public var isEmpty: Bool { entries.isEmpty }
}

/// Matches parsed CSV rows against the wallet and flags duplicates.
public enum ImportPlanner {
    /// A row is a duplicate when an existing record shares its account, kind, amount and timestamp
    /// to the second. That is deliberately strict: re-importing the same export is the case worth
    /// catching, and two genuinely separate purchases rarely collide on all four.
    public static func fingerprint(accountID: UUID?, kind: RecordKind, amount: Decimal, date: Date) -> String {
        let seconds = Int(date.timeIntervalSince1970.rounded())
        return "\(accountID?.uuidString ?? "-")|\(kind.rawValue)|\(RecordCSV.string(from: amount))|\(seconds)"
    }

    public static func plan(rows: [RecordCSVRow], accounts: [Account], categories: [WalletCategory],
                            tags: [WalletTag], existing: [WalletRecord]) -> ImportPlan {
        let accountsByName = index(accounts.map { ($0.name, $0.id) })
        let tagsByName = index(tags.map { ($0.name, $0.id) })
        let categoryIDs = categoryIndex(categories)
        var fingerprints = Set(existing.map {
            fingerprint(accountID: $0.draft.accountID, kind: $0.draft.kind,
                        amount: $0.draft.amount, date: $0.draft.date)
        })

        var entries: [ImportPlan.Entry] = []
        for row in rows {
            let accountID = accountsByName[normalized(row.accountName)]
            let destinationID = row.destinationAccountName.isEmpty
                ? nil : accountsByName[normalized(row.destinationAccountName)]

            var tagIDs: Set<UUID> = []
            var newLabels: [String] = []
            for name in row.labelNames {
                if let id = tagsByName[normalized(name)] { tagIDs.insert(id) } else { newLabels.append(name) }
            }

            var issue: ImportPlan.Issue?
            if accountID == nil {
                issue = .unknownAccount(row.accountName)
            } else if row.kind == .transfer {
                if row.destinationAccountName.isEmpty {
                    issue = .transferNeedsDestination
                } else if destinationID == nil {
                    issue = .unknownDestinationAccount(row.destinationAccountName)
                } else if destinationID == accountID {
                    issue = .transferToSameAccount
                }
            }

            if issue == nil {
                let print = fingerprint(accountID: accountID, kind: row.kind, amount: row.amount, date: row.date)
                // Also catches duplicates within the file itself, not just against the wallet.
                if !fingerprints.insert(print).inserted { issue = .duplicate }
            }

            entries.append(ImportPlan.Entry(row: row, accountID: accountID,
                                            destinationAccountID: destinationID,
                                            categoryID: categoryIDs[normalized(row.categoryPath)],
                                            tagIDs: tagIDs, newLabelNames: newLabels, issue: issue))
        }
        return ImportPlan(entries: entries)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func index(_ pairs: [(String, UUID)]) -> [String: UUID] {
        Dictionary(pairs.map { (normalized($0.0), $0.1) }, uniquingKeysWith: { first, _ in first })
    }

    /// Categories are addressable by full "Parent / Child" path and, when unambiguous, by name.
    private static func categoryIndex(_ categories: [WalletCategory]) -> [String: UUID] {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var index: [String: UUID] = [:]
        for category in categories {
            index[normalized(RecordCSV.path(for: category.id, in: byID))] = category.id
        }
        for category in categories where index[normalized(category.name)] == nil {
            index[normalized(category.name)] = category.id
        }
        return index
    }
}
