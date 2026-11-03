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
/// Date and relevance order are grouped. Relevance over search text would interleave days, so its
/// results are regrouped with the newest day first and the best match first within each day (see
/// `daysByDate`). Amount order is left ungrouped, since sorting by size is the point there and day
/// headers would scatter it. Transfers move money between the user's own accounts, so they are left
/// out of the day net exactly as statistics leaves them out of income and expenses. Days spanning
/// more than one currency report no net rather than adding unlike currencies together.
enum RecordDayGrouping {
    /// Day headers apply to date order and to relevance; amount order stays a flat ranking.
    static func groups(_ sort: RecordSortOrder, hasText: Bool) -> Bool {
        switch sort {
        case .newest, .oldest, .relevance: true
        case .largest, .smallest: false
        }
    }

    /// True when results arrive ranked rather than dated, so days must be put back in date order.
    /// Without search text relevance is already newest first.
    static func daysByDate(_ sort: RecordSortOrder, hasText: Bool) -> Bool {
        sort == .relevance && hasText
    }

    /// Groups results by calendar day. Days appear in the order their first result does, unless
    /// `newestDayFirst` reorders them; records within a day always keep their incoming order, which
    /// for a search is best match first.
    static func sections(for results: [RecordSearchResult], newestDayFirst: Bool = false,
                         calendar: Calendar = .current) -> [RecordDaySection] {
        var order: [Date] = []
        var byDay: [Date: [RecordSearchResult]] = [:]
        for result in results {
            let day = calendar.startOfDay(for: result.record.draft.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(result)
        }
        if newestDayFirst { order.sort(by: >) }
        return order.map { day in
            let entries = byDay[day] ?? []
            let (net, currency) = net(for: entries)
            return RecordDaySection(date: day, results: entries, net: net, currencyCode: currency)
        }
    }

    private static func net(for results: [RecordSearchResult]) -> (Decimal?, String?) {
        let counted = results.map(\.record).filter(\.draft.countsAsActivity)
        let currencies = Set(counted.map(\.currencyCode))
        guard let currency = currencies.first, currencies.count == 1 else { return (nil, nil) }
        let total = counted.reduce(Decimal(0)) { partial, record in
            partial + (record.draft.kind == .income ? record.draft.amount : -record.draft.amount)
        }
        return (total, currency)
    }
}
