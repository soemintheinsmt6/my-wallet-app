import Combine
import Foundation
import WalletDomain

/// A card the dashboard can show.
public enum DashboardCard: String, CaseIterable, Codable, Sendable, Identifiable {
    case balance
    case quickActions
    case summary
    case spendingChart
    case budgets
    case goals
    case bills
    case recent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balance: "Balance"
        case .quickActions: "Quick Actions"
        case .summary: "Income & Expenses"
        case .spendingChart: "Spending Chart"
        case .budgets: "Budget Progress"
        case .goals: "Savings Goals"
        case .bills: "Upcoming Bills"
        case .recent: "Recent Activity"
        }
    }

    public var symbol: String {
        switch self {
        case .balance: "wallet.bifold"
        case .quickActions: "bolt"
        case .summary: "arrow.up.arrow.down"
        case .spendingChart: "chart.bar"
        case .budgets: "chart.bar.fill"
        case .goals: "target"
        case .bills: "calendar.badge.clock"
        case .recent: "list.bullet.rectangle"
        }
    }

    /// Shown on a fresh install, in this order.
    public static let defaultOrder: [DashboardCard] = [
        .balance, .quickActions, .summary, .budgets, .bills, .recent,
    ]
}

/// The window the dashboard's figures cover.
public enum DashboardPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case today
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .month: "This Month"
        }
    }

    public var component: Calendar.Component {
        switch self {
        case .today: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
    }
}

/// What the user has arranged their dashboard to look like.
///
/// Order and visibility are stored separately from the card list, so adding a card in a later
/// release appends it rather than resetting an arrangement the user already made.
public struct DashboardConfiguration: Codable, Sendable, Equatable {
    public var order: [DashboardCard]
    public var hidden: Set<DashboardCard>
    public var period: DashboardPeriod
    /// `nil` means every account included in statistics.
    public var accountID: UUID?

    public init(order: [DashboardCard] = DashboardCard.defaultOrder,
                hidden: Set<DashboardCard> = Set(DashboardCard.allCases)
                    .subtracting(DashboardCard.defaultOrder),
                period: DashboardPeriod = .month, accountID: UUID? = nil) {
        self.order = order
        self.hidden = hidden
        self.period = period
        self.accountID = accountID
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
           let stored = try? JSONDecoder().decode(DashboardConfiguration.self, from: data) {
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
