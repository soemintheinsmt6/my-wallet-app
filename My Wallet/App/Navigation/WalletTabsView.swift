import SwiftUI
import WalletFeature

struct WalletTabsView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject private var accounts: AccountsViewModel
    @State private var selection = WalletTab.home

    init(dependencies: AppDependencies, settings: SettingsViewModel) {
        self.dependencies = dependencies
        self.settings = settings
        accounts = dependencies.accountsViewModel
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(records: dependencies.recordsViewModel,
                     planning: dependencies.planningViewModel,
                     selection: $selection)
                .tabItem { Label(WalletTab.home.title, systemImage: WalletTab.home.symbol) }
                .tag(WalletTab.home)

            RecordsView(viewModel: dependencies.recordsViewModel)
                .tabItem { Label(WalletTab.records.title, systemImage: WalletTab.records.symbol) }
                .tag(WalletTab.records)

            StatisticsView(viewModel: dependencies.recordsViewModel, planning: dependencies.planningViewModel)
                .tabItem { Label(WalletTab.statistics.title, systemImage: WalletTab.statistics.symbol) }
                .tag(WalletTab.statistics)

            PlanningView(viewModel: dependencies.planningViewModel)
                .tabItem { Label(WalletTab.planning.title, systemImage: WalletTab.planning.symbol) }
                .tag(WalletTab.planning)

            MoreView(accounts: dependencies.accountsViewModel,
                     categories: dependencies.categoriesViewModel,
                     tags: dependencies.tagsViewModel,
                     settings: settings,
                     planning: dependencies.planningViewModel)
                .tabItem { Label(WalletTab.more.title, systemImage: WalletTab.more.symbol) }
                .tag(WalletTab.more)
                .badge(accounts.balanceNotifications.count)
        }
        // Discard open drafts/navigation in every window after a successful reset.
        .id(settings.resetGeneration)
        .disabled(settings.isResetting)
        .task { await dependencies.planningViewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await dependencies.planningViewModel.refresh(generate: true) } }
        }
    }
}
