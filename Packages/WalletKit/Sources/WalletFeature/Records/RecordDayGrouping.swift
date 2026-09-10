import Foundation
import WalletDomain

/// One calendar day of the ledger, with the day's net where it can be stated honestly.
struct RecordDaySection: Identifiable, Equatable {
    let date: Date
    let results: [RecordSearchResult]
    /// Net movement for the day, or `nil` when the day mixes currencies or holds only transfers.
    let net: Decimal?
    let currencyCode: String?

    var id: Date { date }
}

/// Groups search results into day sections for the ledger.
///
/// Only date-ordered results are grouped: ranking by relevance over search text, or by amount,
/// interleaves days, and day headers would then be meaningless. Transfers move money between the
/// user's own accounts, so they are left out of the day net exactly as statistics leaves them out
/// of income and expenses. Days spanning more than one currency report no net rather than adding
/// unlike currencies together.
enum RecordDayGrouping {
    /// Day headers only make sense when the list is already in date order.
    static func groups(_ sort: RecordSortOrder, hasText: Bool) -> Bool {
        switch sort {
        case .newest, .oldest: true
        // Relevance falls back to date order until there is text to rank against.
        case .relevance: !hasText
        case .largest, .smallest: false
        }
    }

    static func sections(for results: [RecordSearchResult], calendar: Calendar = .current) -> [RecordDaySection] {
        var order: [Date] = []
        var byDay: [Date: [RecordSearchResult]] = [:]
        for result in results {
            let day = calendar.startOfDay(for: result.record.draft.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(result)
        }
        return order.map { day in
            let entries = byDay[day] ?? []
            let (net, currency) = net(for: entries)
            return RecordDaySection(date: day, results: entries, net: net, currencyCode: currency)
        }
    }

    private static func net(for results: [RecordSearchResult]) -> (Decimal?, String?) {
        let counted = results.map(\.record).filter { $0.draft.kind != .transfer }
        let currencies = Set(counted.map(\.currencyCode))
        guard let currency = currencies.first, currencies.count == 1 else { return (nil, nil) }
        let total = counted.reduce(Decimal(0)) { partial, record in
            partial + (record.draft.kind == .income ? record.draft.amount : -record.draft.amount)
        }
        return (total, currency)
    }
}
