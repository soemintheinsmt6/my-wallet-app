import SwiftUI

/// The five top-level destinations.
///
/// iOS collapses anything past five tabs into its own "More" list, so the secondary destinations
/// (accounts, categories, labels, settings) live behind `MoreView` where they keep real titles and
/// icons instead of a system fallback list.
public enum WalletTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case records
    case statistics
    case planning
    case more

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Dashboard"
        case .records: "Records"
        case .statistics: "Statistics"
        case .planning: "Planning"
        case .more: "More"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .records: "list.bullet.rectangle"
        case .statistics: "chart.pie"
        case .planning: "calendar.badge.clock"
        case .more: "ellipsis.circle"
        }
    }
}
