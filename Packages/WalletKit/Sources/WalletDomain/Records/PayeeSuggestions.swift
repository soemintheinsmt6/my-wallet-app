import Foundation

/// Payees already in the wallet, offered while a payee (or an income's payer) is typed so the same
/// one is spelled the same way each time and its category can be learned from it (see
/// `PayeeCategorizer`).
///
/// Spellings of one payee ("Starbucks", "STARBUCKS #0042", "starbucks") are grouped by the
/// categorizer's key and offered once, under the spelling used most often: a name typed by hand
/// repeats exactly, while a bank's line changes with every store number.
///
/// Payees of the record's own kind come first, so an employer leads for income and a coffee shop
/// for spending; payees recorded under other kinds fill the remaining places, so a kind with few
/// records of its own (income, usually) still offers names already in the wallet.
///
/// Typed text matches the start of a payee or of any word in it, ignoring case and accents. Within
/// each kind, payees the text starts are listed first, then the most used, then the most recently
/// used. With nothing typed, the most recently used are offered.
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

        mutating func add(count: Int, lastUsed date: Date) {
            self.count += count
            lastUsed = max(lastUsed, date)
        }
    }

    private var payees: [RecordKind: [Payee]] = [:]

    public init() {}

    /// Learns every payee but those of balance adjustments, which have none.
    public init(records: [WalletRecord]) {
        // Tally each exact text first: a ledger repeats a few hundred payees across thousands of
        // records, so trimming, folding and keying then run once per distinct text.
        var tallies: [RecordKind: [String: Spelling]] = [:]
        for record in records where !record.draft.isAdjustment && !record.draft.payee.isEmpty {
            tallies[record.draft.kind, default: [:]][record.draft.payee, default: Spelling()]
                .add(count: 1, lastUsed: record.draft.date)
        }
        var keys = PayeeCategorizer.KeyCache()
        for (kind, texts) in tallies {
            var groups: [String: [String: Spelling]] = [:]
            for (text, tally) in texts {
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = keys.key(for: name)
                groups[key.isEmpty ? Self.fold(name) : key, default: [:]][name, default: Spelling()]
                    .add(count: tally.count, lastUsed: tally.lastUsed)
            }
            payees[kind] = groups.values.compactMap { spellings in
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
        guard limit > 0 else { return [] }
        let query = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var offered: [String] = []
        // Folded names already listed, so a payee recorded under two kinds is offered once.
        var seen: Set<String> = []
        let others = RecordKind.allCases.filter { $0 != kind }.flatMap { payees[$0] ?? [] }
        for group in [payees[kind] ?? [], others] {
            for payee in Self.ranked(group, for: query) where offered.count < limit {
                guard seen.insert(payee.folded).inserted else { continue }
                offered.append(payee.name)
            }
        }
        return offered
    }

    private static func ranked(_ payees: [Payee], for query: String) -> [Payee] {
        guard !query.isEmpty else {
            return payees.sorted { ($0.lastUsed, $0.count) > ($1.lastUsed, $1.count) }
        }
        return payees
            .filter { $0.folded != query && startsWord(query, in: $0.folded) }
            .map { (payee: $0, isPrefix: $0.folded.hasPrefix(query)) }
            .sorted { lhs, rhs in
                if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
                return (lhs.payee.count, lhs.payee.lastUsed) > (rhs.payee.count, rhs.payee.lastUsed)
            }
            .map(\.payee)
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
