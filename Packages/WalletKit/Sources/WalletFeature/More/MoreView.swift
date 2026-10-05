import SwiftUI
import WalletDomain

/// The fifth tab: the secondary destinations that used to be tabs six and seven.
///
/// This replaces the system's automatic "More" list so each destination keeps its icon tile,
/// a description and, for accounts, a badge when a balance limit is breached.
public struct MoreView: View {
    @ObservedObject private var accounts: AccountsViewModel
    @ObservedObject private var categories: CategoriesViewModel
    @ObservedObject private var tags: TagsViewModel
    @ObservedObject private var settings: SettingsViewModel
    private let planning: PlanningViewModel?
    private let appLock: AppLockViewModel?
    private let dataExchange: DataExchangeViewModel?
    private let currency: CurrencyViewModel?
    private let insights: InsightsViewModel?
    private let theme: ThemeViewModel?
    private let drinking: DrinkingDaysViewModel?
    private let appIcons: [WalletAppIcon]
    /// Passed through to the categories list so records can be dropped onto a category.
    private let refile: ((Set<UUID>, UUID) async -> Void)?

    public init(accounts: AccountsViewModel, categories: CategoriesViewModel, tags: TagsViewModel,
                settings: SettingsViewModel, planning: PlanningViewModel? = nil,
                appLock: AppLockViewModel? = nil, dataExchange: DataExchangeViewModel? = nil,
                currency: CurrencyViewModel? = nil, insights: InsightsViewModel? = nil,
                theme: ThemeViewModel? = nil, drinking: DrinkingDaysViewModel? = nil,
                appIcons: [WalletAppIcon] = [],
                refile: ((Set<UUID>, UUID) async -> Void)? = nil) {
        self.accounts = accounts
        self.categories = categories
        self.tags = tags
        self.settings = settings
        self.planning = planning
        self.appLock = appLock
        self.dataExchange = dataExchange
        self.currency = currency
        self.insights = insights
        self.theme = theme
        self.drinking = drinking
        self.appIcons = appIcons
        self.refile = refile
    }

    private var alertCount: Int { accounts.balanceNotifications.count }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountsView(viewModel: accounts)
                    } label: {
                        MoreRow(title: "Accounts", detail: accountsDetail,
                                symbol: "wallet.bifold", color: .blue, badge: alertCount)
                    }
                    NavigationLink {
                        CategoriesView(viewModel: categories, planning: planning, refile: refile)
                    } label: {
                        MoreRow(title: "Categories", detail: categoriesDetail, symbol: "folder", color: .orange)
                    }
                    NavigationLink {
                        TagsView(viewModel: tags)
                    } label: {
                        MoreRow(title: "Labels", detail: tagsDetail, symbol: "tag", color: .purple)
                    }
                } header: {
                    Text("Wallet")
                } footer: {
                    Text("Accounts hold balances. Categories and labels organize records.")
                }

                if let drinking {
                    Section {
                        NavigationLink {
                            DrinkingDaysView(viewModel: drinking)
                        } label: {
                            DrinkingMoreRow(viewModel: drinking)
                        }
                    } header: {
                        Text("Personal")
                    } footer: {
                        Text("Kept apart from your wallet and not counted in its statistics.")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView(viewModel: settings, appLock: appLock, dataExchange: dataExchange,
                                     currency: currency, insights: insights,
                                     theme: theme, appIcons: appIcons)
                    } label: {
                        MoreRow(title: "Settings", detail: "Appearance, app lock and app data",
                                symbol: "gearshape", color: .gray)
                    }
                }
            }
            .navigationTitle("More")
        }
        // Each row's subtitle counts what its destination holds, so this screen has to observe all
        // three view models itself — otherwise the counts read zero until the destination is
        // visited and starts its own observer. Separate tasks because `observe()` never returns.
        .task { await accounts.observe() }
        .task { await categories.observe() }
        .task { await tags.observe() }
    }

    private var accountsDetail: String {
        if alertCount > 0 { return alertCount == 1 ? "1 balance alert" : "\(alertCount) balance alerts" }
        let count = accounts.accounts.count
        return count == 1 ? "1 account" : "\(count) accounts"
    }

    private var categoriesDetail: String {
        let count = categories.rootCategories.count
        return count == 1 ? "1 category" : "\(count) categories"
    }

    private var tagsDetail: String {
        let count = tags.tags.count
        return count == 1 ? "1 label" : "\(count) labels"
    }
}

/// Observes the drinking view model itself, since `MoreView` only holds it optionally.
private struct DrinkingMoreRow: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel

    var body: some View {
        MoreRow(title: "Drinking Days", detail: detail, symbol: "wineglass", color: .orange)
            .task { await viewModel.observe() }
    }

    private var detail: String {
        let summary = DrinkingSummary(days: Array(viewModel.days.values), month: viewModel.today,
                                      today: viewModel.today, calendar: viewModel.calendar)
        let count = summary.drinkingDays
        return count == 1 ? "1 drinking day this month" : "\(count) drinking days this month"
    }
}

private struct MoreRow: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    var badge: Int = 0

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: WalletMetrics.small)
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, WalletMetrics.small)
                    .padding(.vertical, WalletMetrics.hair)
                    .background(.red, in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.hair)
        // `detail` already spells out the alert count, so the badge stays decorative.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}
