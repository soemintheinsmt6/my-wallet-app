import Combine
import Foundation
import WalletDomain

/// A card the dashboard can show.
public enum DashboardCard: String, CaseIterable, Codable, Sendable, Identifiable {
    case balance
    case accounts
    case quickActions
    case summary
    case balanceTrend
    case expenseBreakdown
    case topExpenses
    case spendingChart
    case budgets
    case goals
    case bills
    case forecast
    case recent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balance: "Balance"
        case .accounts: "Accounts"
        case .quickActions: "Quick Actions"
        case .summary: "Income & Expenses"
        case .balanceTrend: "Balance Trend"
        case .expenseBreakdown: "Expenses"
        case .topExpenses: "Top Expenses"
        case .spendingChart: "Spending Chart"
        case .budgets: "Budget Progress"
        case .goals: "Savings Goals"
        case .bills: "Upcoming Bills"
        case .forecast: "Cash Flow Forecast"
        case .recent: "Recent Activity"
        }
    }

    public var symbol: String {
        switch self {
        case .balance: WalletSymbols.wallet
        case .accounts: "creditcard"
        case .quickActions: "bolt"
        case .summary: "arrow.up.arrow.down"
        case .balanceTrend: "chart.line.uptrend.xyaxis"
        case .expenseBreakdown: "chart.pie"
        case .topExpenses: "list.number"
        case .spendingChart: "chart.bar"
        case .budgets: "chart.bar.fill"
        case .goals: "target"
        case .bills: "calendar.badge.clock"
        case .forecast: "chart.line.text.clipboard"
        case .recent: "list.bullet.rectangle"
        }
    }

    /// Shown on a fresh install, in this order.
    public static let defaultOrder: [DashboardCard] = [
        .balance, .accounts, .quickActions, .summary, .balanceTrend, .expenseBreakdown, .topExpenses,
        .budgets, .bills, .forecast, .recent,
    ]
}

/// What the user has arranged their dashboard to look like.
///
/// Order and visibility are stored separately from the card list, so adding a card in a later
/// release appends it rather than resetting an arrangement the user already made.
///
/// The dashboard always covers the current month across every account included in statistics;
/// narrower views live in Statistics, Records and each account's own screen. Arrangements saved
/// when the dashboard had its own period and account scope still decode, those keys ignored.
public struct DashboardConfiguration: Codable, Sendable, Equatable {
    public var order: [DashboardCard]
    public var hidden: Set<DashboardCard>

    public init(order: [DashboardCard] = DashboardCard.defaultOrder,
                hidden: Set<DashboardCard> = Set(DashboardCard.allCases)
                    .subtracting(DashboardCard.defaultOrder)) {
        self.order = order
        self.hidden = hidden
    }

    /// Places a card that an older saved arrangement has never seen directly after `anchor`,
    /// rather than letting it append at the bottom. Does nothing once the card is in the order.
    mutating func introduce(_ card: DashboardCard, after anchor: DashboardCard) {
        guard !order.contains(card) else { return }
        if let index = order.firstIndex(of: anchor) {
            order.insert(card, at: index + 1)
        } else {
            order.append(card)
        }
    }

    /// Cards in their arranged order, with anything new appended at the end.
    public var arranged: [DashboardCard] {
        let known = Set(order)
        return order + DashboardCard.allCases.filter { !known.contains($0) }
    }

    public var visible: [DashboardCard] { arranged.filter { !hidden.contains($0) } }

    public func isVisible(_ card: DashboardCard) -> Bool { !hidden.contains(card) }

    public mutating func setVisible(_ card: DashboardCard, _ visible: Bool) {
        if visible { hidden.remove(card) } else { hidden.insert(card) }
        if !order.contains(card) { order.append(card) }
    }

    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        var current = arranged
        current.move(fromOffsets: fromOffsets, toOffset: toOffset)
        order = current
    }
}

/// Owns the dashboard arrangement and persists it.
@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var configuration: DashboardConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            save()
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: WalletPreferenceKeys.dashboard),
           var stored = try? JSONDecoder().decode(DashboardConfiguration.self, from: data) {
            // The account cards replaced the dashboard's account picker; show them where the
            // picker's figures used to lead, not at the bottom of an existing arrangement.
            stored.introduce(.accounts, after: .balance)
            // The chart cards sit together after the month's summary, in this order.
            stored.introduce(.balanceTrend, after: .summary)
            stored.introduce(.expenseBreakdown, after: .balanceTrend)
            stored.introduce(.topExpenses, after: .expenseBreakdown)
            // The forecast reads the same bills, so it follows them.
            stored.introduce(.forecast, after: .bills)
            configuration = stored
        } else {
            configuration = DashboardConfiguration()
        }
    }

    public func reset() { configuration = DashboardConfiguration() }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: WalletPreferenceKeys.dashboard)
    }
}
