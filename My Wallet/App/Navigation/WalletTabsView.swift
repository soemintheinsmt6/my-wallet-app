import CoreSpotlight
import SwiftUI
import WalletDomain
import WalletFeature

/// The compact-width layout: the five tabs.
struct WalletTabsView: View {
    let dependencies: AppDependencies
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject private var accounts: AccountsViewModel
    @Binding var selection: WalletTab
    @Binding var pendingAdd: RecordKind?

    init(dependencies: AppDependencies, settings: SettingsViewModel,
         selection: Binding<WalletTab>, pendingAdd: Binding<RecordKind?>) {
        self.dependencies = dependencies
        self.settings = settings
        accounts = dependencies.accountsViewModel
        _selection = selection
        _pendingAdd = pendingAdd
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(records: dependencies.recordsViewModel,
                     accounts: dependencies.accountsViewModel,
                     planning: dependencies.planningViewModel,
                     currency: dependencies.currencyViewModel,
                     insights: dependencies.insightsViewModel,
                     dashboard: dependencies.dashboardViewModel,
                     debts: dependencies.debtsViewModel,
                     selection: $selection,
                     pendingAdd: $pendingAdd)
                .tabItem { Label(WalletTab.home.title, systemImage: WalletTab.home.symbol) }
                .tag(WalletTab.home)

            RecordsView(viewModel: dependencies.recordsViewModel)
                .tabItem { Label(WalletTab.records.title, systemImage: WalletTab.records.symbol) }
                .tag(WalletTab.records)

            StatisticsView(viewModel: dependencies.recordsViewModel, planning: dependencies.planningViewModel)
                .tabItem { Label(WalletTab.statistics.title, systemImage: WalletTab.statistics.symbol) }
                .tag(WalletTab.statistics)

            PlanningView(viewModel: dependencies.planningViewModel, debts: dependencies.debtsViewModel,
                         splits: dependencies.splitsViewModel)
                .tabItem { Label(WalletTab.planning.title, systemImage: WalletTab.planning.symbol) }
                .tag(WalletTab.planning)

            MoreView(accounts: dependencies.accountsViewModel,
                     categories: dependencies.categoriesViewModel,
                     tags: dependencies.tagsViewModel,
                     settings: settings,
                     planning: dependencies.planningViewModel,
                     appLock: dependencies.appLockViewModel,
                     dataExchange: dependencies.dataExchangeViewModel,
                     currency: dependencies.currencyViewModel,
                     insights: dependencies.insightsViewModel,
                     theme: dependencies.themeViewModel,
                     drinking: dependencies.drinkingDaysViewModel,
                     appIcons: WalletAppIcons.options,
                     refile: dependencies.refileRecords)
                .tabItem { Label(WalletTab.more.title, systemImage: WalletTab.more.symbol) }
                .tag(WalletTab.more)
                .badge(accounts.balanceNotifications.count)
        }
    }

}
