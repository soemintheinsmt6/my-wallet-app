import SwiftUI
import WalletFeature

struct WalletTabsView: View {
    let dependencies: AppDependencies
    @ObservedObject var settings: SettingsViewModel

    var body: some View {
        TabView {
            RecordsView(viewModel: dependencies.recordsViewModel)
                .tabItem { Label("Records", systemImage: "list.bullet.rectangle") }
            AccountsView(viewModel: dependencies.accountsViewModel)
                .tabItem { Label("Accounts", systemImage: "wallet.bifold") }
            CategoriesView(viewModel: dependencies.categoriesViewModel)
                .tabItem { Label("Categories", systemImage: "folder") }
            TagsView(viewModel: dependencies.tagsViewModel)
                .tabItem { Label("Labels", systemImage: "tag") }
            SettingsView(viewModel: settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // Discard open drafts/navigation in every window after a successful reset.
        .id(settings.resetGeneration)
        .disabled(settings.isResetting)
    }
}
