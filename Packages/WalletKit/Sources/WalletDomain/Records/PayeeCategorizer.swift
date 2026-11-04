import Foundation

/// Suggests a category for a payee from the records already filed under that payee.
///
/// Nothing is stored: the suggestions are learned afresh from the ledger, so they follow every
/// edit, sync with the records themselves and need no schema of their own.
///
/// Payees are compared by a key that ignores case, accents, punctuation, store and reference
/// numbers, and card-processor prefixes, so "STARBUCKS #1234" from a bank and "Starbucks" typed by
/// hand are the same payee. A bank description that only starts with a known payee ("GRAB TRIP
/// SINGAPORE" after "Grab") takes that payee's category, the longest known start winning.
///
/// When a payee has been filed under several categories, the most recent record wins: people
/// re-file a payee when their habits change, and the newest record says how they file it now.
public struct PayeeCategorizer: Sendable {
    private struct Learned: Sendable {
        let categoryID: UUID
        let date: Date
    }

    /// Words that card processors and banks put before the merchant's name.
    static let prefixWords: Set<String> = [
        "pos", "eftpos", "visa", "mastercard", "mc", "debit", "credit", "card", "purchase", "payment",
        "contactless", "sq", "tst", "sp", "paypal", "pp", "ach", "dd", "fpi", "fpo",
    ]
    /// Shorter keys are too common to file anything under from the start of a description alone.
    private static let minimumPrefixLength = 3

    private var learned: [RecordKind: [String: Learned]] = [:]

    public init() {}

    /// Learns from income and expense records with a payee and a category that still exists.
    /// Transfers and balance adjustments are not filed under categories, so they teach nothing.
    public init(records: [WalletRecord], categories: [WalletCategory]) {
        let existing = Set(categories.map(\.id))
        var keys = KeyCache()
        for record in records {
            let draft = record.draft
            guard draft.countsAsActivity, let categoryID = draft.categoryID, existing.contains(categoryID) else { continue }
            let key = keys.key(for: draft.payee)
            guard !key.isEmpty else { continue }
            if let current = learned[draft.kind]?[key], current.date >= draft.date { continue }
            learned[draft.kind, default: [:]][key] = Learned(categoryID: categoryID, date: draft.date)
        }
    }

    public var isEmpty: Bool { learned.values.allSatisfy(\.isEmpty) }

    /// The category last used for this payee and kind, or `nil` when it has never been filed.
    public func category(forPayee payee: String, kind: RecordKind) -> UUID? {
        guard let table = learned[kind], !table.isEmpty else { return nil }
        var words = Self.words(in: payee)
        while !words.isEmpty {
            let key = words.joined(separator: " ")
            if let match = table[key] { return match.categoryID }
            words.removeLast()
            if words.joined(separator: " ").count < Self.minimumPrefixLength { break }
        }
        return nil
    }

    /// The payee as it is compared: lowercased words without accents, numbers or processor prefixes.
    public static func key(for payee: String) -> String {
        words(in: payee).joined(separator: " ")
    }

    /// Keys worked out once per distinct payee text. A ledger repeats the same few hundred payees
    /// across thousands of records, and folding and splitting each one is most of the build time.
    struct KeyCache {
        private var keys: [String: String] = [:]

        mutating func key(for payee: String) -> String {
            if let key = keys[payee] { return key }
            let key = PayeeCategorizer.key(for: payee)
            keys[payee] = key
            return key
        }
    }

    private static func words(in payee: String) -> [String] {
        let folded = payee.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var words = folded
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            // Store, terminal and reference numbers differ on every statement line.
            .filter { word in !word.contains { $0.isNumber } }
        while let first = words.first, prefixWords.contains(first), words.count > 1 {
            words.removeFirst()
        }
        // A description of nothing but processor words ("CARD PAYMENT") names no payee.
        if words.count == 1, let only = words.first, prefixWords.contains(only) { return [] }
        return words
    }
}
