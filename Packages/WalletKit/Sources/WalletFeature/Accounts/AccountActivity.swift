import Foundation
import WalletDomain

/// A calendar window an account's activity can be viewed over: the one containing a date.
public enum ActivityPeriod: String, CaseIterable, Sendable, Identifiable {
    case day
    case week
    case month
    case year

    public var id: String { rawValue }

    /// Short labels for a segmented control.
    public var title: String {
        switch self {
        case .day: "Today"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    public var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
    }
}

/// One account's records and income/expense totals over a window.
///
/// Totals count only income and expenses booked to this account, matching the labels the summary
/// card uses; transfers move money between the user's own accounts, so they are listed but left
/// out of both totals, as are balance adjustments. Unlike Statistics, an account excluded from statistics still shows its own
/// activity here — excluding it hides it from the wallet-wide figures, not from itself.
public struct AccountActivity: Equatable, Sendable {
    public let income: Decimal
    public let expenses: Decimal
    /// Records that touch the account in the window, newest first, transfers in either direction
    /// included.
    public let records: [WalletRecord]

    public init(records: [WalletRecord], accountID: UUID, interval: DateInterval) {
        let touching = records.filter { record in
            let draft = record.draft
            guard draft.date >= interval.start, draft.date < interval.end else { return false }
            return draft.accountID == accountID || draft.destinationAccountID == accountID
        }
        let own = touching.filter { $0.draft.accountID == accountID && $0.draft.countsAsActivity }
        income = own.filter { $0.draft.kind == .income }.reduce(0) { $0 + $1.draft.amount }
        expenses = own.filter { $0.draft.kind == .expense }.reduce(0) { $0 + $1.draft.amount }
        self.records = touching.sorted { $0.draft.date > $1.draft.date }
    }
}
