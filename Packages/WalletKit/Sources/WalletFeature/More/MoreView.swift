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

    public init(accounts: AccountsViewModel, categories: CategoriesViewModel, tags: TagsViewModel,
                settings: SettingsViewModel, planning: PlanningViewModel? = nil,
                appLock: AppLockViewModel? = nil) {
        self.accounts = accounts
        self.categories = categories
        self.tags = tags
        self.settings = settings
        self.planning = planning
        self.appLock = appLock
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
                        CategoriesView(viewModel: categories, planning: planning)
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

                Section {
                    NavigationLink {
                        SettingsView(viewModel: settings, appLock: appLock)
                    } label: {
                        MoreRow(title: "Settings", detail: "Appearance, app lock and app data",
                                symbol: "gearshape", color: .gray)
                    }
                }
            }
            .navigationTitle("More")
        }
        .task { await accounts.observe() }
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
