import SwiftUI
import WalletDomain
import WalletFeature

/// The regular-width layout: a sidebar of destinations beside their content.
///
/// Used on iPad and macOS, where a tab bar wastes the width available. Home and Statistics share
/// the detail area side by side, because on a large screen the summary and the charts are read
/// together rather than one after the other.
struct WalletSidebarView: View {
    let dependencies: AppDependencies
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject var commands: WalletCommandBus
    @Binding var selection: WalletTab
    @Binding var pendingAdd: RecordKind?

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // iOS requires an optional selection binding; the sidebar always has one selected, so
            // a cleared selection simply keeps the previous tab rather than emptying the detail.
            List(WalletTab.allCases, selection: Binding<WalletTab?>(
                get: { selection },
                set: { if let new = $0 { selection = new } }
            )) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationTitle("My Wallet")
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            #endif
        } detail: {
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .home:
            // The dashboard and its charts, read together.
            HStack(spacing: 0) {
                HomeView(records: dependencies.recordsViewModel,
                         planning: dependencies.planningViewModel,
                         currency: dependencies.currencyViewModel,
                         insights: dependencies.insightsViewModel,
                     dashboard: dependencies.dashboardViewModel,
                     debts: dependencies.debtsViewModel,
                         selection: $selection,
                         pendingAdd: $pendingAdd)
                Divider()
                StatisticsView(viewModel: dependencies.recordsViewModel,
                               planning: dependencies.planningViewModel)
            }
        case .records:
            RecordsView(viewModel: dependencies.recordsViewModel)
        case .statistics:
            StatisticsView(viewModel: dependencies.recordsViewModel,
                           planning: dependencies.planningViewModel)
        case .planning:
            PlanningView(viewModel: dependencies.planningViewModel, debts: dependencies.debtsViewModel,
                         splits: dependencies.splitsViewModel)
        case .more:
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
                     appIcons: WalletAppIcons.options,
                     refile: dependencies.refileRecords)
        }
    }
}
