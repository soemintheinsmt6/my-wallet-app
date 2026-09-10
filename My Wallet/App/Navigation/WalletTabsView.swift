import SwiftUI
import WalletFeature

struct WalletTabsView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var settings: SettingsViewModel

    var body: some View {
        TabView {
            RecordsView(viewModel: dependencies.recordsViewModel)
                .tabItem { Label("Records", systemImage: "list.bullet.rectangle") }
            StatisticsView(viewModel: dependencies.recordsViewModel, planning: dependencies.planningViewModel)
                .tabItem { Label("Statistics", systemImage: "chart.pie") }
            AccountsView(viewModel: dependencies.accountsViewModel)
                .tabItem { Label("Accounts", systemImage: "wallet.bifold") }
            CategoriesView(viewModel: dependencies.categoriesViewModel, planning: dependencies.planningViewModel)
                .tabItem { Label("Categories", systemImage: "folder") }
            TagsView(viewModel: dependencies.tagsViewModel)
                .tabItem { Label("Labels", systemImage: "tag") }
            PlanningView(viewModel: dependencies.planningViewModel)
                .tabItem { Label("Planning", systemImage: "calendar.badge.clock") }
            SettingsView(viewModel: settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
