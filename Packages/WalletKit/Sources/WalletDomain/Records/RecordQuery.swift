import Foundation

public enum RecordSortOrder: String, CaseIterable, Sendable, Identifiable {
    case relevance, newest, oldest, largest, smallest
    public var id: String { rawValue }
}

/// Combined free-text search and filter criteria for the record ledger.
///
/// An empty collection means "no restriction" rather than "match nothing". `end` and
/// `maximumAmount` bounds are exclusive and inclusive respectively, matching the
/// ledger conventions used by statistics and reports.
public struct RecordQuery: Sendable, Equatable {
    public var text: String
    public var kinds: Set<RecordKind>
    public var accountIDs: Set<UUID>
    public var categoryIDs: Set<UUID>
    public var tagIDs: Set<UUID>
    public var paymentTypes: Set<PaymentType>
    public var start: Date?
    public var end: Date?
    public var minimumAmount: Decimal?
    public var maximumAmount: Decimal?
    public var sort: RecordSortOrder

    public init(text: String = "", kinds: Set<RecordKind> = [], accountIDs: Set<UUID> = [],
                categoryIDs: Set<UUID> = [], tagIDs: Set<UUID> = [], paymentTypes: Set<PaymentType> = [],
                start: Date? = nil, end: Date? = nil, minimumAmount: Decimal? = nil,
                maximumAmount: Decimal? = nil, sort: RecordSortOrder = .relevance) {
        self.text = text
        self.kinds = kinds
        self.accountIDs = accountIDs
        self.categoryIDs = categoryIDs
        self.tagIDs = tagIDs
        self.paymentTypes = paymentTypes
        self.start = start
        self.end = end
        self.minimumAmount = minimumAmount
        self.maximumAmount = maximumAmount
        self.sort = sort
    }

    /// Whitespace-separated terms; every term must match at least one searched field.
    public var terms: [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var hasText: Bool { !terms.isEmpty }

    /// Number of filter groups in use, for a filter badge. Text and sorting are not filters.
    public var activeFilterCount: Int {
        var count = 0
        if !kinds.isEmpty { count += 1 }
        if !accountIDs.isEmpty { count += 1 }
        if !categoryIDs.isEmpty { count += 1 }
        if !tagIDs.isEmpty { count += 1 }
        if !paymentTypes.isEmpty { count += 1 }
        if start != nil || end != nil { count += 1 }
        if minimumAmount != nil || maximumAmount != nil { count += 1 }
        return count
    }

    public var isActive: Bool { hasText || activeFilterCount > 0 }

    /// Clears every filter group. Search text and the chosen sort order are preserved.
    public mutating func clearFilters() {
        kinds = []
        accountIDs = []
        categoryIDs = []
        tagIDs = []
        paymentTypes = []
        start = nil
        end = nil
        minimumAmount = nil
        maximumAmount = nil
    }
}
