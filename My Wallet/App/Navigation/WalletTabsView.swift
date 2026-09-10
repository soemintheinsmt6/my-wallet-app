import CoreSpotlight
import SwiftUI
import WalletDomain
import WalletFeature

struct WalletTabsView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject private var accounts: AccountsViewModel
    @ObservedObject private var records: RecordsViewModel
    @State private var selection = WalletTab.home
    @State private var pendingAdd: RecordKind?

    init(dependencies: AppDependencies, settings: SettingsViewModel) {
        self.dependencies = dependencies
        self.settings = settings
        accounts = dependencies.accountsViewModel
        records = dependencies.recordsViewModel
    }

    /// Keeps Spotlight in step with the wallet's names.
    private func indexSpotlight() {
        dependencies.spotlightIndexer.index(accounts: records.accounts, categories: records.categories)
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(records: dependencies.recordsViewModel,
                     planning: dependencies.planningViewModel,
                     currency: dependencies.currencyViewModel,
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

            PlanningView(viewModel: dependencies.planningViewModel)
                .tabItem { Label(WalletTab.planning.title, systemImage: WalletTab.planning.symbol) }
                .tag(WalletTab.planning)

            MoreView(accounts: dependencies.accountsViewModel,
                     categories: dependencies.categoriesViewModel,
                     tags: dependencies.tagsViewModel,
                     settings: settings,
                     planning: dependencies.planningViewModel,
                     appLock: dependencies.appLockViewModel,
                     dataExchange: dependencies.dataExchangeViewModel,
                     currency: dependencies.currencyViewModel)
                .tabItem { Label(WalletTab.more.title, systemImage: WalletTab.more.symbol) }
                .tag(WalletTab.more)
                .badge(accounts.balanceNotifications.count)
        }
        // Reaches the record editor and detail without threading through every presenter.
        .environment(\.currencyViewModel, dependencies.currencyViewModel)
        // Discard open drafts/navigation in every window after a successful reset.
        .id(settings.resetGeneration)
        .disabled(settings.isResetting)
        .task { await dependencies.planningViewModel.observe() }
        .task { dependencies.snapshotCoordinator.start() }
        .task { dependencies.watchConnector.activate() }
        // Names, not counts: a rename must reindex too. The indexer skips identical passes.
        .onChange(of: records.accounts.map(\.name)) { _, _ in indexSpotlight() }
        .onChange(of: records.categories.map(\.name)) { _, _ in indexSpotlight() }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let tab = WalletSpotlightIndexer.destination(for: identifier) else { return }
            selection = tab
        }
        .onOpenURL { url in open(url) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await dependencies.planningViewModel.refresh(generate: true) } }
        }
    }

    /// Routes a widget deep link. Quick-add lands on Home, which owns the editor sheet.
    private func open(_ url: URL) {
        guard let link = WalletDeepLink(url: url) else { return }
        switch link {
        case .home: selection = .home
        case .records: selection = .records
        case .statistics: selection = .statistics
        case .planning: selection = .planning
        case .addRecord(let kind):
            selection = .home
            pendingAdd = kind
        }
    }
}
