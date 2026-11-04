import Foundation

/// Which of a record's amounts an import changes to match the bank.
public enum RecordAmountField: Sendable, Equatable {
    /// What left the record's account; for income and expenses, the whole amount.
    case amount
    /// What a transfer delivered to its destination in another currency.
    case receivedAmount
}

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
        /// The file named no category this wallet has, and `categoryID` is the one last used for
        /// the row's payee in the wallet's own records.
        public let hasLearnedCategory: Bool
        /// For a date-only row, the existing record it matched.
        public let match: LedgerMatcher.Match?
        /// How the matched record's amount would change to what the bank moved, or `nil` when they
        /// agree or the record cannot be changed on one side alone (a same-currency transfer).
        public let amountUpdate: AmountUpdate?
        /// The row's position among the parsed rows, stable across re-planning.
        public let rowIndex: Int

        public var isImportable: Bool { issue == nil }

        /// The matched record's date and time, which may be a few days before the row's own date.
        public var matchedRecordDate: Date? { match?.date }
        /// What the matched record moved through the row's account.
        public var matchedRecordAmount: Decimal? { match?.amount }

        /// The matched record's amount when it is not the row's, so the review can point it out.
        public var differingMatchedAmount: Decimal? {
            guard let matchedRecordAmount, matchedRecordAmount != row.amount else { return nil }
            return matchedRecordAmount
        }

        public init(id: UUID = UUID(), row: RecordCSVRow, accountID: UUID?, destinationAccountID: UUID?,
                    categoryID: UUID?, tagIDs: Set<UUID>, newLabelNames: [String], issue: Issue?,
                    isUncategorized: Bool = false, hasLearnedCategory: Bool = false,
                    match: LedgerMatcher.Match? = nil, amountUpdate: AmountUpdate? = nil, rowIndex: Int = 0) {
            self.hasLearnedCategory = hasLearnedCategory
            self.match = match
            self.amountUpdate = amountUpdate
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

    /// Bringing a matched record's amount in line with the bank: a tip, a fee or a settled
    /// exchange rate the person could not know when they entered it.
    public struct AmountUpdate: Sendable, Equatable {
        public let recordID: UUID
        public let field: RecordAmountField
        public let from: Decimal
        public let to: Decimal

        public init(recordID: UUID, field: RecordAmountField, from: Decimal, to: Decimal) {
            self.recordID = recordID
            self.field = field
            self.from = from
            self.to = to
        }

        /// Applies this change to the record's draft.
        public func apply(to draft: inout RecordDraft) {
            switch field {
            case .amount: draft.amount = to
            case .receivedAmount: draft.receivedAmount = to
            }
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

    /// Rows to be imported under the category last used for their payee.
    public var learnedCategoryCount: Int { importable.count { $0.hasLearnedCategory } }

    /// Bank rows recognised as records already in the wallet, so the review can show what each
    /// matched and the person can spot a wrong match.
    public var matchedToRecords: [Entry] { entries.filter { $0.matchedRecordDate != nil } }

    /// Matched records whose amount would change to the bank's.
    public var amountUpdates: [AmountUpdate] { entries.compactMap(\.amountUpdate) }

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
    /// Income and expense rows whose category the wallet does not have take the category last used
    /// for their payee in `categorizer`, else the fallback chosen for their kind in
    /// `fallbackCategoryIDs`, and without either cannot be imported.
    ///
    /// Rows at `unmatchedRowIndices` are ones the person chose to import despite a match, so they
    /// are left out of matching and the record they matched is free for another row.
    public static func plan(rows: [RecordCSVRow], accounts: [Account], categories: [WalletCategory],
                            tags: [WalletTag], existing: [WalletRecord],
                            fallbackCategoryIDs: [RecordKind: UUID] = [:],
                            categorizer: PayeeCategorizer? = nil,
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
        let recordsByID = matches.isEmpty ? [:]
            : Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currencies = Dictionary(accounts.map { ($0.id, $0.currencyCode) }, uniquingKeysWith: { first, _ in first })

        var entries: [ImportPlan.Entry] = []
        for (index, row) in rows.enumerated() {
            let (accountID, destinationID, resolvedIssue) = resolved[index]
            let match = matches[index]
            var issue = match == nil ? resolvedIssue : .duplicate

            var tagIDs: Set<UUID> = []
            var newLabels: [String] = []
            for name in row.labelNames {
                if let id = tagsByName[normalized(name)] { tagIDs.insert(id) } else { newLabels.append(name) }
            }

            let category = category(for: row, in: categoryIDs, categorizer: categorizer,
                                    fallbackCategoryIDs: fallbackCategoryIDs)
            if category.isUncategorized, category.id == nil, issue == nil { issue = .needsCategory(row.categoryPath) }

            entries.append(ImportPlan.Entry(row: row, accountID: accountID,
                                            destinationAccountID: destinationID,
                                            categoryID: category.id,
                                            tagIDs: tagIDs, newLabelNames: newLabels, issue: issue,
                                            isUncategorized: category.isUncategorized,
                                            hasLearnedCategory: category.isLearned, match: match,
                                            amountUpdate: match.flatMap {
                                                amountUpdate(for: $0, row: row, record: recordsByID[$0.recordID],
                                                             currencies: currencies)
                                            },
                                            rowIndex: index))
        }
        return ImportPlan(entries: entries)
    }

    /// The category the file names, else the one last used for the row's payee, else the fallback
    /// for its kind. Transfers and adjustments carry no category.
    private static func category(for row: RecordCSVRow, in categoryIDs: [String: UUID], categorizer: PayeeCategorizer?,
                                 fallbackCategoryIDs: [RecordKind: UUID])
        -> (id: UUID?, isLearned: Bool, isUncategorized: Bool) {
        guard row.kind != .transfer, !row.isAdjustment else { return (categoryIDs[normalized(row.categoryPath)], false, false) }
        if let named = categoryIDs[normalized(row.categoryPath)] { return (named, false, false) }
        if let learned = categorizer?.category(forPayee: row.payee, kind: row.kind) { return (learned, true, false) }
        return (fallbackCategoryIDs[row.kind], false, true)
    }

    /// The change that brings a matched record to the bank's amount. A same-currency transfer moves
    /// one amount out and in, so one bank's statement cannot change it without contradicting the other.
    private static func amountUpdate(for match: LedgerMatcher.Match, row: RecordCSVRow, record: WalletRecord?,
                                     currencies: [UUID: String]) -> ImportPlan.AmountUpdate? {
        guard match.amount != row.amount, let draft = record?.draft else { return nil }
        guard draft.kind == .transfer else {
            return ImportPlan.AmountUpdate(recordID: match.recordID, field: .amount, from: match.amount, to: row.amount)
        }
        guard let source = draft.accountID.flatMap({ currencies[$0] }),
              let destination = draft.destinationAccountID.flatMap({ currencies[$0] }),
              source != destination else { return nil }
        return ImportPlan.AmountUpdate(recordID: match.recordID, field: match.side == .source ? .amount : .receivedAmount,
                                       from: match.amount, to: row.amount)
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
/// A row matches a record moving money the same way through the same account, dated the same day
/// or up to `postingLagDays` earlier, because a bank posts a purchase a day or more after it was
/// made, never before. The amounts must agree, or differ by at most `amountTolerance` of the
/// bank's amount: a card charge in another currency or a rounded entry settles slightly off what
/// was typed. A transfer counts as money out of its source account and money in to its destination
/// at its received amount, so a transfer entered by hand matches both banks' statements.
///
/// A tip is added after the bill is entered, so an expense the bank charged more for, by up to
/// `tipTolerance` of the entered amount, matches too. That band is wide enough to catch unrelated
/// purchases, so it is tried last and only against records no other row matched: an entered bill
/// whose own bank row is in the statement is taken by that row first.
///
/// Matching is one-for-one: two identical coffees on one day are two purchases, so each record
/// absorbs one row. Matches are settled in rounds, each for every row before the next: exact
/// amount on the same day, then exact amount within the lag, then a near amount, then a tip. So a
/// row is never beaten to its exact match by a looser one. Within a round the closest earlier
/// record wins, then the closest amount.
public struct LedgerMatcher {
    public static let postingLagDays = 3
    /// The largest difference still treated as the same transaction, as a fraction of the bank's amount.
    public static let amountTolerance = Decimal(string: "0.05")!
    /// The largest tip recognised, as a fraction of the amount entered.
    public static let tipTolerance = Decimal(string: "0.25")!

    public enum MatchKind: Sendable, Equatable {
        case exact, near, tip
    }

    /// Which part of a record a row matched: a transfer moves money out of its source and in to
    /// its destination, each of which can appear on a different statement.
    public enum Side: Sendable, Equatable {
        case source, destination
    }

    /// The record a row matched.
    public struct Match: Sendable, Equatable {
        public let recordID: UUID
        public let side: Side
        public let kind: MatchKind
        public let date: Date
        /// What the record moved through this account, which may differ from the row.
        public let amount: Decimal

        public init(recordID: UUID, side: Side, kind: MatchKind, date: Date, amount: Decimal) {
            self.recordID = recordID
            self.side = side
            self.kind = kind
            self.date = date
            self.amount = amount
        }
    }

    private struct Leg {
        let recordID: UUID
        let side: Side
        /// An expense that is not a balance adjustment, so a tip can have been added to it.
        let isBill: Bool
        let date: Date
        let amount: Decimal

        /// A record and which side of it, so a transfer's two accounts are matched separately.
        var id: String { "\(recordID.uuidString)|\(side)" }
    }

    /// Legs by account, direction and calendar day, so a row reads only the days in its window.
    private var legs: [String: [Leg]] = [:]
    private let calendar = Calendar.current

    public init(existing: [WalletRecord]) {
        for record in existing {
            let draft = record.draft
            guard let accountID = draft.accountID else { continue }
            switch draft.kind {
            case .expense: add(record, side: .source, account: accountID, direction: "out", amount: draft.amount)
            case .income: add(record, side: .source, account: accountID, direction: "in", amount: draft.amount)
            case .transfer:
                // A transfer row in the app's own date-only CSV, or a debit on the source's statement.
                add(record, side: .source, account: accountID, direction: "transfer", amount: draft.amount)
                add(record, side: .source, account: accountID, direction: "out", amount: draft.amount)
                if let destination = draft.destinationAccountID {
                    add(record, side: .destination, account: destination, direction: "in",
                        amount: draft.receivedAmount ?? draft.amount)
                }
            }
        }
    }

    private mutating func add(_ record: WalletRecord, side: Side, account: UUID, direction: String, amount: Decimal) {
        let leg = Leg(recordID: record.id, side: side, isBill: record.draft.kind == .expense && !record.draft.isAdjustment,
                      date: record.draft.date, amount: amount)
        legs[key(account: account, direction: direction, day: record.draft.date), default: []].append(leg)
    }

    private func key(account: UUID, direction: String, day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(account.uuidString)|\(direction)|\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// A matching round: how far back to look, and which amounts count.
    private struct Round {
        let days: ClosedRange<Int>
        let kind: MatchKind

        /// Whether a record of `entered` can be the bank's `charged`, and how far apart they are.
        func difference(entered leg: Leg, charged row: RecordCSVRow) -> Decimal? {
            let difference = abs(leg.amount - row.amount)
            switch kind {
            case .exact:
                return difference == 0 ? 0 : nil
            case .near:
                return difference <= row.amount * LedgerMatcher.amountTolerance ? difference : nil
            case .tip:
                // Only on top of a bill the bank charged more for, never a transfer or an adjustment.
                guard row.kind == .expense, leg.isBill, row.amount > leg.amount,
                      difference <= leg.amount * LedgerMatcher.tipTolerance else { return nil }
                return difference
            }
        }
    }

    private static let rounds = [Round(days: 0...0, kind: .exact),
                                 Round(days: 1...postingLagDays, kind: .exact),
                                 Round(days: 0...postingLagDays, kind: .near),
                                 Round(days: 0...postingLagDays, kind: .tip)]

    private static func direction(of kind: RecordKind) -> String {
        switch kind {
        case .expense: "out"
        case .income: "in"
        case .transfer: "transfer"
        }
    }

    /// The matched record for each candidate row that has one, keyed by the row's index.
    public func match(_ candidates: [(index: Int, row: RecordCSVRow, accountID: UUID)]) -> [Int: Match] {
        var consumed = Set<String>()
        var matched: [Int: Match] = [:]
        for round in Self.rounds {
            for candidate in candidates where matched[candidate.index] == nil {
                let row = candidate.row
                let direction = Self.direction(of: row.kind)
                var best: (leg: Leg, days: Int, difference: Decimal)?
                for days in round.days {
                    guard let day = calendar.date(byAdding: .day, value: -days, to: row.date) else { continue }
                    for leg in legs[key(account: candidate.accountID, direction: direction, day: day)] ?? []
                    where !consumed.contains(leg.id) {
                        guard let difference = round.difference(entered: leg, charged: row) else { continue }
                        // Closest day, then closest amount, then the earliest record for a stable choice.
                        if let current = best,
                           (current.days, current.difference, current.leg.date) <= (days, difference, leg.date) {
                            continue
                        }
                        best = (leg, days, difference)
                    }
                }
                if let best {
                    consumed.insert(best.leg.id)
                    matched[candidate.index] = Match(recordID: best.leg.recordID, side: best.leg.side, kind: round.kind,
                                                     date: best.leg.date, amount: best.leg.amount)
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
