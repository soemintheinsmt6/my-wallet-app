import Foundation

/// Payees already in the wallet, offered while a payee is typed so the same one is spelled the
/// same way each time and its category can be learned from it (see `PayeeCategorizer`).
///
/// Spellings of one payee ("Starbucks", "STARBUCKS #0042", "starbucks") are grouped by the
/// categorizer's key and offered once, under the spelling used most often: a name typed by hand
/// repeats exactly, while a bank's line changes with every store number. Payees are kept per kind,
/// so an employer is not offered for a coffee.
///
/// Typed text matches the start of a payee or of any word in it, ignoring case and accents. Payees
/// it starts are listed first, then the most used, then the most recently used. With nothing
/// typed, the most recently used are offered.
public struct PayeeSuggestions: Sendable {
    private struct Payee: Sendable {
        let name: String
        /// The name folded for matching, computed once rather than on every keystroke.
        let folded: String
        let count: Int
        let lastUsed: Date
    }

    private struct Spelling {
        var count = 0
        var lastUsed = Date.distantPast
    }

    private var payees: [RecordKind: [Payee]] = [:]

    public init() {}

    /// Learns every payee but those of balance adjustments, which have none.
    public init(records: [WalletRecord]) {
        var groups: [RecordKind: [String: [String: Spelling]]] = [:]
        for record in records where !record.draft.isAdjustment {
            let name = record.draft.payee.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = PayeeCategorizer.key(for: name)
            let group = key.isEmpty ? Self.fold(name) : key
            var spelling = groups[record.draft.kind, default: [:]][group, default: [:]][name, default: Spelling()]
            spelling.count += 1
            spelling.lastUsed = max(spelling.lastUsed, record.draft.date)
            groups[record.draft.kind, default: [:]][group, default: [:]][name] = spelling
        }
        for (kind, byGroup) in groups {
            payees[kind] = byGroup.values.compactMap { spellings in
                guard let best = spellings.max(by: { ($0.value.count, $0.value.lastUsed) < ($1.value.count, $1.value.lastUsed) })
                else { return nil }
                return Payee(name: best.key, folded: Self.fold(best.key),
                             count: spellings.values.reduce(0) { $0 + $1.count },
                             lastUsed: spellings.values.map(\.lastUsed).max() ?? best.value.lastUsed)
            }
        }
    }

    /// Up to `limit` payees for what has been typed so far, leaving out the one already typed.
    public func suggestions(for text: String, kind: RecordKind, limit: Int = 5) -> [String] {
        guard let all = payees[kind], limit > 0 else { return [] }
        let query = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else {
            return all.sorted { ($0.lastUsed, $0.count) > ($1.lastUsed, $1.count) }.prefix(limit).map(\.name)
        }
        return all
            .filter { $0.folded != query && Self.startsWord(query, in: $0.folded) }
            .map { (payee: $0, isPrefix: $0.folded.hasPrefix(query)) }
            .sorted { lhs, rhs in
                if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
                return (lhs.payee.count, lhs.payee.lastUsed) > (rhs.payee.count, rhs.payee.lastUsed)
            }
            .prefix(limit)
            .map(\.payee.name)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether `query` occurs in `name` at its start or just after a space or punctuation, so
    /// "ele" finds "7-Eleven" and "cof" finds "Blue Bottle Coffee" but "ucks" finds nothing.
    private static func startsWord(_ query: String, in name: String) -> Bool {
        var searchStart = name.startIndex
        while let range = name.range(of: query, range: searchStart..<name.endIndex) {
            if range.lowerBound == name.startIndex { return true }
            let before = name[name.index(before: range.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            searchStart = name.index(after: range.lowerBound)
        }
        return false
    }
}
