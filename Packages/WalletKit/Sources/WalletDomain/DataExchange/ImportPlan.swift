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
        /// An income or expense row whose file named no category this wallet has, so `categoryID`
        /// is the import's fallback for its kind, or `nil` when none was chosen.
        public let isUncategorized: Bool
        /// For a date-only row matched to an existing record, that record's date and time, which
        /// may be a few days before the row's own date.
        public let matchedRecordDate: Date?
        /// The row's position among the parsed rows, stable across re-planning.
        public let rowIndex: Int

        public var isImportable: Bool { issue == nil }

        public init(id: UUID = UUID(), row: RecordCSVRow, accountID: UUID?, destinationAccountID: UUID?,
                    categoryID: UUID?, tagIDs: Set<UUID>, newLabelNames: [String], issue: Issue?,
                    isUncategorized: Bool = false, matchedRecordDate: Date? = nil, rowIndex: Int = 0) {
            self.matchedRecordDate = matchedRecordDate
            self.rowIndex = rowIndex
            self.id = id
            self.row = row
            self.accountID = accountID
            self.destinationAccountID = destinationAccountID
            self.categoryID = categoryID
            self.tagIDs = tagIDs
            self.newLabelNames = newLabelNames
            self.issue = issue
            self.isUncategorized = isUncategorized
        }
    }

    /// Why a row cannot be imported as-is.
    public enum Issue: Sendable, Equatable {
        case duplicate
        case unknownAccount(String)
        case unknownDestinationAccount(String)
        case transferNeedsDestination
        case transferToSameAccount
        /// Income and expenses need a category; the file named none this wallet has (the text it
        /// gave, possibly empty) and no fallback was chosen for the row's kind.
        case needsCategory(String)

        public var message: String {
            switch self {
            case .duplicate: "Already in your wallet"
            case .unknownAccount(let name): "No account named “\(name)”"
            case .unknownDestinationAccount(let name): "No destination account named “\(name)”"
            case .transferNeedsDestination: "Transfer has no destination account"
            case .transferToSameAccount: "Transfer source and destination match"
            case .needsCategory(let path) where path.isEmpty: "No category; choose one for rows without"
            case .needsCategory(let path): "No category named “\(path)”; choose one for rows without"
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

    /// Kinds with rows the file left uncategorised, so the review can offer a fallback for each.
    public var uncategorizedKinds: Set<RecordKind> {
        Set(entries.filter { $0.isUncategorized && $0.issue != .duplicate }.map(\.row.kind))
    }

    /// Bank rows recognised as records already in the wallet, so the review can show what each
    /// matched and the person can spot a wrong match.
    public var matchedToRecords: [Entry] { entries.filter { $0.matchedRecordDate != nil } }

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

    ///
    /// Rows without a time of day (bank statements) are matched by day instead, against records
    /// imported earlier and entered by hand alike; see `LedgerMatcher`.
    ///
    /// Income and expense rows whose category the wallet does not have take the fallback chosen
    /// for their kind in `fallbackCategoryIDs`, and without one cannot be imported.
    ///
    /// Rows at `unmatchedRowIndices` are ones the person chose to import despite a match, so they
    /// are left out of matching and the record they matched is free for another row.
    public static func plan(rows: [RecordCSVRow], accounts: [Account], categories: [WalletCategory],
                            tags: [WalletTag], existing: [WalletRecord],
                            fallbackCategoryIDs: [RecordKind: UUID] = [:],
                            unmatchedRowIndices: Set<Int> = []) -> ImportPlan {
        let accountsByName = index(accounts.map { ($0.name, $0.id) })
        let tagsByName = index(tags.map { ($0.name, $0.id) })
        let categoryIDs = categoryIndex(categories)
        var timedDuplicates = TimedDuplicateMatcher(existing: existing)

        // Resolve every row first: date-only rows are matched as a batch, so a row with an exact
        // same-day match is never beaten to it by an earlier row that only matches within the lag.
        var resolved: [(accountID: UUID?, destinationID: UUID?, issue: ImportPlan.Issue?)] = []
        var dateOnlyCandidates: [Int] = []
        for (index, row) in rows.enumerated() {
            let accountID = accountsByName[normalized(row.accountName)]
            let destinationID = row.destinationAccountName.isEmpty
                ? nil : accountsByName[normalized(row.destinationAccountName)]
            var issue = accountIssue(for: row, accountID: accountID, destinationID: destinationID)
            if issue == nil {
                if row.isDateOnly {
                    if !unmatchedRowIndices.contains(index) { dateOnlyCandidates.append(index) }
                } else if timedDuplicates.matches(row, accountID: accountID) {
                    issue = .duplicate
                }
            }
            resolved.append((accountID, destinationID, issue))
        }
        let matches = LedgerMatcher(existing: existing).match(dateOnlyCandidates.compactMap { index in
            resolved[index].accountID.map { (index: index, row: rows[index], accountID: $0) }
        })

        var entries: [ImportPlan.Entry] = []
        for (index, row) in rows.enumerated() {
            let (accountID, destinationID, resolvedIssue) = resolved[index]
            let matchedDate = matches[index]
            var issue = matchedDate == nil ? resolvedIssue : .duplicate

            var tagIDs: Set<UUID> = []
            var newLabels: [String] = []
            for name in row.labelNames {
                if let id = tagsByName[normalized(name)] { tagIDs.insert(id) } else { newLabels.append(name) }
            }

            // Transfers and adjustments carry no category.
            let needsCategory = row.kind != .transfer && !row.isAdjustment
            var categoryID = categoryIDs[normalized(row.categoryPath)]
            let isUncategorized = needsCategory && categoryID == nil
            if isUncategorized {
                categoryID = fallbackCategoryIDs[row.kind]
                if categoryID == nil, issue == nil { issue = .needsCategory(row.categoryPath) }
            }

            entries.append(ImportPlan.Entry(row: row, accountID: accountID,
                                            destinationAccountID: destinationID,
                                            categoryID: categoryID,
                                            tagIDs: tagIDs, newLabelNames: newLabels, issue: issue,
                                            isUncategorized: isUncategorized, matchedRecordDate: matchedDate,
                                            rowIndex: index))
        }
        return ImportPlan(entries: entries)
    }

    private static func accountIssue(for row: RecordCSVRow, accountID: UUID?, destinationID: UUID?) -> ImportPlan.Issue? {
        guard accountID != nil else { return .unknownAccount(row.accountName) }
        guard row.kind == .transfer else { return nil }
        if row.destinationAccountName.isEmpty { return .transferNeedsDestination }
        guard let destinationID else { return .unknownDestinationAccount(row.destinationAccountName) }
        return destinationID == accountID ? .transferToSameAccount : nil
    }

    /// Exact-second matching for rows with a time, as the app's own exports have.
    private struct TimedDuplicateMatcher {
        private let existing: Set<String>
        private var seen = Set<String>()

        init(existing: [WalletRecord]) {
            self.existing = Set(existing.map {
                fingerprint(accountID: $0.draft.accountID, kind: $0.draft.kind, amount: $0.draft.amount, date: $0.draft.date)
            })
        }

        /// Also catches duplicates within the file itself, not just against the wallet.
        mutating func matches(_ row: RecordCSVRow, accountID: UUID?) -> Bool {
            let print = fingerprint(accountID: accountID, kind: row.kind, amount: row.amount, date: row.date)
            return existing.contains(print) || !seen.insert(print).inserted
        }
    }
}

/// Matches bank rows, which have a day but no time, to records already in the wallet, whether
/// imported earlier or entered by hand.
///
/// A row matches a record moving the same amount the same way through the same account, dated
/// the same day or up to `postingLagDays` earlier, because a bank posts a purchase a day or more
/// after it was made, never before. A transfer counts as money out of its source account and money
/// in to its destination, so a transfer entered by hand matches both banks' statements.
///
/// Matching is one-for-one: two identical coffees on one day are two purchases, so each record
/// absorbs one row. Same-day matches are made for every row before any lagged one, so a row with
/// an exact match is never beaten to it; within the lag the closest earlier record wins.
public struct LedgerMatcher {
    public static let postingLagDays = 3

    private struct Leg {
        /// A record and which side of it, so a transfer's two accounts are matched separately.
        let id: String
        let day: Date
        let date: Date
    }

    private var legs: [String: [Leg]] = [:]
    private let calendar = Calendar.current

    public init(existing: [WalletRecord]) {
        for record in existing {
            let draft = record.draft
            guard let accountID = draft.accountID else { continue }
            switch draft.kind {
            case .expense: add(record, side: "source", account: accountID, direction: "out", amount: draft.amount)
            case .income: add(record, side: "source", account: accountID, direction: "in", amount: draft.amount)
            case .transfer:
                // A transfer row in the app's own date-only CSV, or a debit on the source's statement.
                add(record, side: "source", account: accountID, direction: "transfer", amount: draft.amount)
                add(record, side: "source", account: accountID, direction: "out", amount: draft.amount)
                if let destination = draft.destinationAccountID {
                    add(record, side: "destination", account: destination, direction: "in",
                        amount: draft.receivedAmount ?? draft.amount)
                }
            }
        }
    }

    private mutating func add(_ record: WalletRecord, side: String, account: UUID, direction: String, amount: Decimal) {
        let leg = Leg(id: "\(record.id.uuidString)|\(side)", day: calendar.startOfDay(for: record.draft.date),
                      date: record.draft.date)
        legs[Self.key(account: account, direction: direction, amount: amount), default: []].append(leg)
    }

    private static func key(account: UUID, direction: String, amount: Decimal) -> String {
        "\(account.uuidString)|\(direction)|\(RecordCSV.string(from: amount))"
    }

    private static func direction(of kind: RecordKind) -> String {
        switch kind {
        case .expense: "out"
        case .income: "in"
        case .transfer: "transfer"
        }
    }

    /// The matched record's date for each candidate row that has one, keyed by the row's index.
    public func match(_ candidates: [(index: Int, row: RecordCSVRow, accountID: UUID)]) -> [Int: Date] {
        var consumed = Set<String>()
        var matched: [Int: Date] = [:]
        for lag in [0...0, 1...Self.postingLagDays] {
            for candidate in candidates where matched[candidate.index] == nil {
                let key = Self.key(account: candidate.accountID, direction: Self.direction(of: candidate.row.kind),
                                   amount: candidate.row.amount)
                let rowDay = calendar.startOfDay(for: candidate.row.date)
                let best = (legs[key] ?? [])
                    .filter { !consumed.contains($0.id) }
                    .compactMap { leg -> (leg: Leg, days: Int)? in
                        guard let days = calendar.dateComponents([.day], from: leg.day, to: rowDay).day,
                              lag.contains(days) else { return nil }
                        return (leg, days)
                    }
                    .min { ($0.days, $0.leg.date) < ($1.days, $1.leg.date) }
                if let best {
                    consumed.insert(best.leg.id)
                    matched[candidate.index] = best.leg.date
                }
            }
        }
        return matched
    }
}

extension ImportPlanner {

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
