import Foundation

public struct RecordSearchResult: Identifiable, Sendable, Equatable {
    public let record: WalletRecord
    /// Higher is a better text match. Zero when the query has no text.
    public let score: Int
    public var id: UUID { record.id }

    public init(record: WalletRecord, score: Int) {
        self.record = record
        self.score = score
    }
}

/// Pure filtering and ranking over already-loaded records.
///
/// Text is matched case- and diacritic-insensitively against the payee, note, category name
/// (including its parent), label names and the amounts. Every term must match at least one
/// of those fields. Filters intersect across groups and union inside a group; selecting a
/// root category also matches its subcategories. Ordering is fully deterministic so that
/// equal scores, dates and amounts do not reshuffle between reloads.
public enum RecordSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func run(records: [WalletRecord], categories: [WalletCategory] = [],
                           tags: [WalletTag] = [], query: RecordQuery) -> [RecordSearchResult] {
        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tagNames = Dictionary(tags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let selectedCategories = expanded(query.categoryIDs, categories: categories)
        let terms = query.terms
        var results: [RecordSearchResult] = []
        for record in records where matches(record, query: query, categories: selectedCategories) {
            guard !terms.isEmpty else {
                results.append(RecordSearchResult(record: record, score: 0))
                continue
            }
            let fields = fields(for: record, categories: categoriesByID, tagNames: tagNames)
            var total = 0
            var matchedEveryTerm = true
            for term in terms {
                let value = score(for: term, fields: fields)
                guard value > 0 else { matchedEveryTerm = false; break }
                total += value
            }
            if matchedEveryTerm { results.append(RecordSearchResult(record: record, score: total)) }
        }
        return sorted(results, by: query.sort)
    }

    /// Root selections include their subcategories; a subcategory selection matches only itself.
    private static func expanded(_ selection: Set<UUID>, categories: [WalletCategory]) -> Set<UUID> {
        guard !selection.isEmpty else { return [] }
        var result = selection
        for category in categories {
            if let parent = category.parentID, selection.contains(parent) { result.insert(category.id) }
        }
        return result
    }

    private static func matches(_ record: WalletRecord, query: RecordQuery, categories: Set<UUID>) -> Bool {
        let draft = record.draft
        if !query.kinds.isEmpty, !query.kinds.contains(draft.kind) { return false }
        if !query.accountIDs.isEmpty {
            let involved = [draft.accountID, draft.destinationAccountID].compactMap { $0 }
            guard involved.contains(where: query.accountIDs.contains) else { return false }
        }
        if !categories.isEmpty {
            guard let id = draft.categoryID, categories.contains(id) else { return false }
        }
        if !query.tagIDs.isEmpty, draft.tagIDs.isDisjoint(with: query.tagIDs) { return false }
        if !query.paymentTypes.isEmpty, !query.paymentTypes.contains(draft.paymentType) { return false }
        if let start = query.start, draft.date < start { return false }
        if let end = query.end, draft.date >= end { return false }
        if let minimum = query.minimumAmount, draft.amount < minimum { return false }
        if let maximum = query.maximumAmount, draft.amount > maximum { return false }
        return true
    }

    private struct Fields {
        var payee = ""
        var note = ""
        var categoryNames: [String] = []
        var tagNames: [String] = []
        var amounts: [Decimal] = []
    }

    private static func fields(for record: WalletRecord, categories: [UUID: WalletCategory],
                               tagNames: [UUID: String]) -> Fields {
        let draft = record.draft
        var fields = Fields()
        fields.payee = draft.payee
        fields.note = draft.note
        if let id = draft.categoryID, let category = categories[id] {
            fields.categoryNames.append(category.name)
            if let parent = category.parentID, let root = categories[parent] { fields.categoryNames.append(root.name) }
        }
        fields.tagNames = draft.tagIDs.compactMap { tagNames[$0] }
        fields.amounts = [draft.amount] + [draft.receivedAmount].compactMap { $0 }
        return fields
    }

    private static func score(for term: String, fields: Fields) -> Int {
        var best = weight(term, fields.payee, exact: 100, prefix: 70, contains: 45)
        for name in fields.categoryNames { best = max(best, weight(term, name, exact: 80, prefix: 55, contains: 35)) }
        for name in fields.tagNames { best = max(best, weight(term, name, exact: 75, prefix: 50, contains: 30)) }
        best = max(best, weight(term, fields.note, exact: 60, prefix: 25, contains: 15))
        return max(best, amountScore(term, fields.amounts))
    }

    private static func weight(_ term: String, _ value: String, exact: Int, prefix: Int, contains: Int) -> Int {
        guard !value.isEmpty, value.range(of: term, options: options) != nil else { return 0 }
        if value.compare(term, options: options) == .orderedSame { return exact }
        let words = value.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.range(of: term, options: options.union(.anchored)) != nil }) { return prefix }
        return contains
    }

    /// Numeric terms match an exact amount first, then a leading or embedded digit run,
    /// so "12" finds 12.50 before 112. Grouping separators are not part of the stored value.
    private static func amountScore(_ term: String, _ amounts: [Decimal]) -> Int {
        let normalized = term.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return 0 }
        let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        var best = 0
        for amount in amounts {
            if let value, amount == value { best = max(best, 90); continue }
            let text = "\(amount)"
            if text.hasPrefix(normalized) { best = max(best, 40) }
            else if text.contains(normalized) { best = max(best, 20) }
        }
        return best
    }

    private static func sorted(_ results: [RecordSearchResult], by order: RecordSortOrder) -> [RecordSearchResult] {
        results.sorted { first, second in
            switch order {
            case .relevance:
                if first.score != second.score { return first.score > second.score }
                return newerFirst(first, second)
            case .newest:
                return newerFirst(first, second)
            case .oldest:
                if first.record.draft.date != second.record.draft.date {
                    return first.record.draft.date < second.record.draft.date
                }
                return identifierOrder(first, second)
            case .largest:
                if first.record.draft.amount != second.record.draft.amount {
                    return first.record.draft.amount > second.record.draft.amount
                }
                return newerFirst(first, second)
            case .smallest:
                if first.record.draft.amount != second.record.draft.amount {
                    return first.record.draft.amount < second.record.draft.amount
                }
                return newerFirst(first, second)
            }
        }
    }

    private static func newerFirst(_ first: RecordSearchResult, _ second: RecordSearchResult) -> Bool {
        if first.record.draft.date != second.record.draft.date {
            return first.record.draft.date > second.record.draft.date
        }
        return identifierOrder(first, second)
    }

    private static func identifierOrder(_ first: RecordSearchResult, _ second: RecordSearchResult) -> Bool {
        first.record.id.uuidString < second.record.id.uuidString
    }
}
