import SwiftUI
import WalletFeature

struct AppRootView: View {
    @ObservedObject var bootstrap: AppBootstrap
    @State private var attempt = 0

    var body: some View {
        Group {
            if let dependencies = bootstrap.dependencies {
                TabView {
                    RecordsView(viewModel: dependencies.recordsViewModel)
                        .tabItem { Label("Records", systemImage: "list.bullet.rectangle") }
                    AccountsView(viewModel: dependencies.accountsViewModel)
                        .tabItem { Label("Accounts", systemImage: "wallet.bifold") }
                    CategoriesView(viewModel: dependencies.categoriesViewModel)
                        .tabItem { Label("Categories", systemImage: "folder") }
                    TagsView(viewModel: dependencies.tagsViewModel)
                        .tabItem { Label("Labels", systemImage: "tag") }
                }
            } else if let startupError = bootstrap.errorMessage {
                ContentUnavailableView {
                    Label("Unable to Open Wallet", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(startupError)
                } actions: {
                    Button("Retry") { attempt += 1 }
                }
            } else {
                ProgressView("Opening wallet…")
            }
        }
        .task(id: attempt) {
            await bootstrap.load()
        }
    }
}
